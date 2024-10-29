//
//  ExpandedOutlineGroup.swift
//  AudioTag
//
//  Created by foyoodo on 28/10/2024.
//

import SwiftUI

protocol ExpandedObservable: AnyObject, Observable {
    var isExpanded: Bool { get set }
}

struct ExpandedOutlineGroup<Data, ID, Parent, Leaf, Subgroup> where Data: RandomAccessCollection, ID: Hashable {
    let root: Data.Element
    let children: KeyPath<Data.Element, Data?>

    @ViewBuilder let content: (Data.Element) -> Leaf
    @ViewBuilder let subgroup: (Data) -> Subgroup
}

extension ExpandedOutlineGroup: View where Parent: View, Leaf: View, Subgroup: View {
    var body: some View {
        if let subroot = root[keyPath: children] {
            subgroup(subroot)
        } else {
            content(root)
        }
    }
}

extension ExpandedOutlineGroup where ID == Data.Element.ID, Parent: View, Parent == Leaf, Subgroup == DisclosureGroup<Parent, AnyView>, Data.Element: Identifiable {
    init<DataElement>(
        _ root: DataElement,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement: Identifiable, DataElement == Data.Element {
        self.init(root: root, children: children, content: content) { subroot in
            DisclosureGroup {
                AnyView(
                    ForEach(subroot) { leaf in
                        ExpandedOutlineGroup(leaf, children: children, content: content)
                    }
                )
            } label: {
                content(root)
            }
        }
    }

    init<DataElement>(
        _ root: DataElement,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement: Identifiable & ExpandedObservable, DataElement == Data.Element {
        self.init(root: root, children: children, content: content) { subroot in
            @Bindable var root = root
            DisclosureGroup(isExpanded: $root.isExpanded) {
                AnyView(
                    ForEach(subroot) { leaf in
                        ExpandedOutlineGroup(leaf, children: children, content: content)
                    }
                )
            } label: {
                content(root)
            }
        }
    }
}
