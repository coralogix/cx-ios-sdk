//
//  UserContext.swift
//
//  Created by Coralogix DEV TEAM on 02/04/2024.
//

import Foundation

public struct UserContext: Equatable {
    let userId: String
    let userName: String
    let userEmail: String
    let userMetadata: [String: String]
    
    public init(userId: String, userName: String, userEmail: String, userMetadata: [String: String]) {
        self.userId = userId
        self.userName = userName
        self.userEmail = userEmail
        self.userMetadata = userMetadata
    }
    
    public func getDictionary() -> [String: Any] {
        return [Keys.userId.rawValue: self.userId,
                Keys.userName.rawValue: self.userName,
                Keys.userEmail.rawValue: self.userEmail,
                Keys.userMetadata.rawValue: self.userMetadata]
    }
    
    public static func == (lhs: UserContext, rhs: UserContext) -> Bool {
        return lhs.userId == rhs.userId && lhs.userName == rhs.userName
    }
}
