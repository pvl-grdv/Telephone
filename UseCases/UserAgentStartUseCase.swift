//
//  UserAgentStartUseCase.swift
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

@MainActor
public final class UserAgentStartUseCase: Sendable {
    private let agent: UserAgent

    public init(agent: UserAgent) {
        self.agent = agent
    }
}

extension UserAgentStartUseCase: UseCase {
    public func execute() {
        agent.maxCalls = 30
        agent.start()
    }
}
