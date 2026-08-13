import SwiftUI

struct KnownWordsView: View {
    @ObservedObject var store: KnownWordsStore
    @State private var newWord = ""
    @State private var editing: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(localized("Words listed here always count as real English — useful for a domain, brand, or handle the system dictionary doesn't know, so it corrects reliably when typed on the wrong layout."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(12)

            List {
                ForEach(store.words, id: \.self) { word in
                    WordRow(
                        word: word,
                        onEdit: { editing = word; newWord = word },
                        onDelete: { remove(word) }
                    )
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                TextField(localized("Add a word…"), text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button(editing == nil ? localized("Add") : localized("Save")) {
                    addWord()
                }
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                if editing != nil {
                    Button(localized("Cancel")) {
                        editing = nil
                        newWord = ""
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 340, minHeight: 420)
    }

    private func addWord() {
        if let old = editing {
            remove(old)
        }
        store.add(newWord)
        newWord = ""
        editing = nil
    }

    private func remove(_ word: String) {
        guard let index = store.words.firstIndex(of: word) else { return }
        store.remove(at: IndexSet(integer: index))
    }
}
