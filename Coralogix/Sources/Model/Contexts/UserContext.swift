//
//  UserContext.swift
//
//  Created by Coralogix DEV TEAM on 02/04/2024.
//

import Foundation
import CoralogixInternal

public struct UserContext: Equatable {
    let userId: String
    let userName: String
    let userEmail: String
    let userMetadata: [String: String]
    let accountId: String?
    let accountName: String?
    
    public init(userId: String,
                userName: String,
                userEmail: String,
                userMetadata: [String: String],
                accountId: String? = nil,
                accountName: String? = nil) {
        self.userId = userId
        self.userName = userName
        self.userEmail = userEmail
        self.userMetadata = userMetadata
        self.accountId = accountId
        self.accountName = accountName
    }
    
    public func getDictionary() -> [String: Any] {
        var result: [String: Any] = [Keys.userId.rawValue: self.userId,
                                     Keys.userName.rawValue: self.userName,
                                     Keys.userEmail.rawValue: self.userEmail,
                                     Keys.userMetadata.rawValue: self.userMetadata]
        if let accountId = self.accountId { result[Keys.accountId.rawValue] = accountId }
        if let accountName = self.accountName { result[Keys.accountName.rawValue] = accountName }
        return result
    }
    
    public static func == (lhs: UserContext, rhs: UserContext) -> Bool {
        return lhs.userId == rhs.userId && lhs.userName == rhs.userName
    }
}
