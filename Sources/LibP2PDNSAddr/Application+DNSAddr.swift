//
//  Application+DNSAddr.swift
//  
//
//  Created by Brandon Toms on 6/22/22.
//

import LibP2P

extension Application.Resolvers.Provider {
    public static var dnsaddr: Self {
        .init { app in
            app.resolvers.use {
                DNSAddr(application: $0)
            }
        }
    }
}
