import SwiftUI

struct ExceptionsView: View {
    @ObservedObject var store: ExceptionListStore
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            Text(localized("Words listed here are never touched by the RU/EN switcher."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(12)

            List {
                ForEach(Array(store.words.enumerated()), id: \.element) { _, word in
                    Text(word)
                }
                .onDelete { store.remove(at: $0) }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                TextField(localized("Add a word…"), text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button(localized("Add"), action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 340, minHeight: 420)
    }

    private func addWord() {
        store.add(newWord)
        newWord = ""
    }
}
