//
//  MealPlanCell.swift
//  Slice 4.3: a single day × meal-slot cell in the weekly planner.
//  Item chips are `.draggable` (carrying the item's UUID string) and the
//  whole cell is a `.dropDestination(for: String.self)`, so a chip can be
//  dragged from any cell and dropped here to reassign its day/slot.
//
//  We carry the UUID as a plain String rather than a custom Transferable
//  type: it's the smallest reliable payload across SwiftUI drag sessions
//  on iOS (a custom UTType adds friction with no benefit for an in-app
//  move). Haptics fire on a successful drop (medium impact) per the slice
//  plan's interaction spec.
//

import SwiftUI

struct MealPlanCell: View {
    @Environment(\.appTheme) private var theme

    let day: Int
    let mealType: MealType
    let items: [MealPlanItem]
    let onAdd: () -> Void
    /// Called with the dragged item's id when something is dropped here.
    let onDropItem: (UUID) -> Void
    let onRemove: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if items.isEmpty {
                emptyDropZone
            } else {
                ForEach(items) { item in
                    chip(item)
                }
                addButton
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? theme.accent.opacity(0.18) : theme.surfaceSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? theme.accent : Color.clear,
                              style: StrokeStyle(lineWidth: 1.5, dash: [4]))
        )
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let raw = droppedIDs.first, let uuid = UUID(uuidString: raw) else { return false }
            PlanHaptics.impact(.medium)
            onDropItem(uuid)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: mealType.icon)
                .font(.system(size: 12))
                .foregroundStyle(items.isEmpty ? theme.textTertiary : theme.accent)
            Text(mealType.label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
    }

    private func chip(_ item: MealPlanItem) -> some View {
        HStack(spacing: 6) {
            Text(item.productName)
                .font(theme.font.caption)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if item.servings != 1 {
                Text(servingsBadge(item.servings))
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(item.id.uuidString) {
            // Drag preview: a compact pill so the system shadow looks
            // intentional rather than a clipped full-width row.
            Text(item.productName)
                .font(theme.font.caption)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.accent.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
        }
        .contextMenu {
            Button(role: .destructive) {
                onRemove(item.id)
            } label: {
                Label("mealplan.remove", systemImage: "trash")
            }
        }
    }

    private var addButton: some View {
        Button(action: {
            PlanHaptics.selection()
            onAdd()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("mealplan.add")
                    .font(theme.font.caption)
            }
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var emptyDropZone: some View {
        Button(action: {
            PlanHaptics.selection()
            onAdd()
        }) {
            HStack {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                Spacer()
            }
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func servingsBadge(_ s: Double) -> String {
        if s == s.rounded() { return "×\(Int(s))" }
        return String(format: "×%.1f", s)
    }
}
