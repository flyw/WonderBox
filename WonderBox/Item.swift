//
//  Item.swift
//  WonderBox
//
//  Created by Yuan Wang on 2026/10/21.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
