//
//  CRXConcurrentCrashGuard.m
//  CoralogixBootstrap
//
//  Everything reached from `crx_guardHandler` runs in a signal handler on a crashed thread: it
//  calls only async-signal-safe functions and Mach traps — the ones PLCrashReporter's own handler
//  uses — and never allocates or takes a lock.
//

#import "CRXConcurrentCrashGuard.h"
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>

/// The signals PLCrashReporter's signal handler is registered for.
static const int crx_guardedSignals[] = {SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP};
#define CRX_GUARDED_SIGNAL_COUNT (sizeof(crx_guardedSignals) / sizeof(crx_guardedSignals[0]))

/// How long a thread that crashed while another crash is handled waits for the process to end.
/// Writing a report takes well under this; the bound only keeps a handler that never returns
/// from turning the crash into a hang.
static const unsigned crx_waitSeconds = 10;

/// Written by `install` before the guard is installed for that signal, and read-only afterwards.
static struct sigaction crx_previousActions[CRX_GUARDED_SIGNAL_COUNT];
static atomic_flag crx_installed = ATOMIC_FLAG_INIT;
static _Atomic(uintptr_t) crx_handlingThread = 0;

static const struct sigaction *crx_previousAction(int signo) {
    for (size_t i = 0; i < CRX_GUARDED_SIGNAL_COUNT; i++) {
        if (crx_guardedSignals[i] == signo) return &crx_previousActions[i];
    }
    return NULL;
}

/// The signal is blocked while its handler runs, so the raised one is delivered — with the
/// default action — as soon as the handler returns.
static void crx_restoreDefaultAndRaise(int signo) {
    struct sigaction fallback;
    memset(&fallback, 0, sizeof fallback);
    fallback.sa_handler = SIG_DFL;
    sigemptyset(&fallback.sa_mask);
    sigaction(signo, &fallback, NULL);
    raise(signo);
}

/// Does what the system would have done for `signo` had the guard never been installed.
static void crx_handOver(int signo, siginfo_t *info, void *uap) {
    const struct sigaction *previous = crx_previousAction(signo);
    if (previous == NULL) {
        crx_restoreDefaultAndRaise(signo);
    } else if (previous->sa_flags & SA_SIGINFO) {
        if (previous->sa_sigaction != NULL) {
            previous->sa_sigaction(signo, info, uap);
        } else {
            crx_restoreDefaultAndRaise(signo);
        }
    } else if (previous->sa_handler == SIG_DFL) {
        crx_restoreDefaultAndRaise(signo);
    } else if (previous->sa_handler != SIG_IGN) {
        previous->sa_handler(signo);
    }
}

typedef struct {
    thread_act_array_t threads;
    mach_msg_type_number_t count;
} crx_suspension;

static crx_suspension crx_suspendOtherThreads(void) {
    crx_suspension suspension = {NULL, 0};
    if (task_threads(mach_task_self(), &suspension.threads, &suspension.count) != KERN_SUCCESS) {
        return (crx_suspension){NULL, 0};
    }
    mach_port_t current = mach_thread_self();
    for (mach_msg_type_number_t i = 0; i < suspension.count; i++) {
        if (suspension.threads[i] != current) thread_suspend(suspension.threads[i]);
    }
    mach_port_deallocate(mach_task_self(), current);
    return suspension;
}

/// Reached only when the handler handed over to returns with the process still meant to run.
/// PLCrashReporter suspends the threads again itself, so after its report they stay stopped.
static void crx_resume(crx_suspension suspension) {
    if (suspension.threads == NULL) return;
    mach_port_t current = mach_thread_self();
    for (mach_msg_type_number_t i = 0; i < suspension.count; i++) {
        if (suspension.threads[i] != current) thread_resume(suspension.threads[i]);
        mach_port_deallocate(mach_task_self(), suspension.threads[i]);
    }
    mach_port_deallocate(mach_task_self(), current);
    vm_deallocate(mach_task_self(), (vm_address_t)suspension.threads,
                  sizeof(thread_t) * suspension.count);
}

static void crx_guardHandler(int signo, siginfo_t *info, void *uap) {
    uintptr_t current = (uintptr_t)pthread_self();
    for (;;) {
        uintptr_t handling = 0;
        if (atomic_compare_exchange_strong(&crx_handlingThread, &handling, current)) break;

        // A fault inside the guard itself: let the default action end the process.
        if (handling == current) {
            crx_restoreDefaultAndRaise(signo);
            return;
        }

        // Another thread's crash is being written and ends the process when it is. Waiting keeps
        // this thread from the default action, which would end it before the report is complete.
        for (unsigned waited = 0; atomic_load(&crx_handlingThread) != 0 && waited < crx_waitSeconds; waited++) {
            sleep(1);
        }
        if (atomic_load(&crx_handlingThread) != 0) {
            crx_restoreDefaultAndRaise(signo);
            return;
        }
        // The other crash was survived after all; this thread's fault is handled in its turn.
    }

    // Before handing over: PLCrashReporter resets every crash signal to its default action as it
    // starts, and a thread that faulted after that would end the process mid-report.
    crx_suspension suspension = crx_suspendOtherThreads();
    crx_handOver(signo, info, uap);
    crx_resume(suspension);
    atomic_store(&crx_handlingThread, 0);
}

@implementation CRXConcurrentCrashGuard

+ (BOOL)install {
    if (atomic_flag_test_and_set(&crx_installed)) return NO;

    struct sigaction guard;
    memset(&guard, 0, sizeof guard);
    // As PLCrashReporter registers its own, so a stack overflow still reaches it on the thread
    // that has the alternate signal stack.
    guard.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&guard.sa_mask);
    guard.sa_sigaction = crx_guardHandler;

    for (size_t i = 0; i < CRX_GUARDED_SIGNAL_COUNT; i++) {
        // Read first and installed second, so the guard is never called before it knows what to
        // hand over to.
        if (sigaction(crx_guardedSignals[i], NULL, &crx_previousActions[i]) != 0) continue;
        sigaction(crx_guardedSignals[i], &guard, NULL);
    }
    return YES;
}

+ (BOOL)isHandlingEverySignal {
    for (size_t i = 0; i < CRX_GUARDED_SIGNAL_COUNT; i++) {
        struct sigaction current;
        if (sigaction(crx_guardedSignals[i], NULL, &current) != 0) return NO;
        if (!(current.sa_flags & SA_SIGINFO) || current.sa_sigaction != crx_guardHandler) return NO;
    }
    return YES;
}

+ (BOOL)handsOverToItself {
    for (size_t i = 0; i < CRX_GUARDED_SIGNAL_COUNT; i++) {
        const struct sigaction *previous = &crx_previousActions[i];
        if ((previous->sa_flags & SA_SIGINFO) && previous->sa_sigaction == crx_guardHandler) return YES;
    }
    return NO;
}

@end
