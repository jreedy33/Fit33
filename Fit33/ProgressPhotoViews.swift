import SwiftUI
import UIKit

// MARK: - Capture View

struct ProgressPhotoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var photoService = ProgressPhotoService.shared
    
    @State private var selectedType: PhotoType = .front
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var photoNotes: String = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    typeSelector
                    
                    photoPreviewArea
                    
                    if capturedImage != nil {
                        notesField
                        saveButton
                    } else {
                        captureButtons
                    }
                    
                    ghostOverlayHint
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
                .padding(.bottom, 60)
            }
            .background(
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                ProgressPhotoCameraPicker(image: $capturedImage, sourceType: .camera)
            }
            .sheet(isPresented: $showingLibrary) {
                ProgressPhotoCameraPicker(image: $capturedImage, sourceType: .photoLibrary)
            }
        }
    }
    
    private var typeSelector: some View {
        Picker("Photo Type", selection: $selectedType) {
            ForEach(PhotoType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }
    
    private var photoPreviewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardBackground)
                .frame(height: 400)
            
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        Button(action: { capturedImage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.ds_heading1)
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                        .padding(Spacing.sm),
                        alignment: .topTrailing
                    )
            } else {
                // Ghost overlay of previous photo
                if let lastPhoto = photoService.latestPhoto(ofType: selectedType),
                   let lastImage = photoService.loadImage(for: lastPhoto) {
                    Image(uiImage: lastImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(0.25)
                        .overlay(
                            VStack {
                                Text("Previous \(selectedType.displayName)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(Capsule().fill(.black.opacity(0.5)))
                            }
                            .padding(Spacing.sm),
                            alignment: .topLeading
                        )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Take a \(selectedType.displayName) photo")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var captureButtons: some View {
        HStack(spacing: 16) {
            Button(action: { showingCamera = true }) {
                Label("Camera", systemImage: "camera.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    )
            }
            
            Button(action: { showingLibrary = true }) {
                Label("Library", systemImage: "photo.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cardBackground)
                    )
            }
        }
    }
    
    private var notesField: some View {
        TextField("Add a note (optional)", text: $photoNotes)
            .font(.subheadline)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.gray.opacity(0.08))
            )
    }
    
    private var saveButton: some View {
        Button(action: savePhoto) {
            HStack {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Photo")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            )
        }
        .disabled(isSaving)
    }
    
    private var ghostOverlayHint: some View {
        Group {
            if photoService.latestPhoto(ofType: selectedType) != nil && capturedImage == nil {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Ghost overlay shows your last photo to help match the same pose")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, Spacing.md)
            }
        }
    }
    
    private func savePhoto() {
        guard let image = capturedImage else { return }
        isSaving = true
        HapticManager.notification(.success)
        
        let notes = photoNotes.isEmpty ? nil : photoNotes
        _ = photoService.savePhoto(image: image, type: selectedType, notes: notes)
        
        isSaving = false
        dismiss()
    }
}

// MARK: - Camera Picker

struct ProgressPhotoCameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        if sourceType == .camera {
            picker.cameraDevice = .front
        }
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProgressPhotoCameraPicker
        init(_ parent: ProgressPhotoCameraPicker) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let edited = info[.editedImage] as? UIImage {
                parent.image = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.image = original
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Gallery View

struct ProgressPhotoGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var photoService = ProgressPhotoService.shared
    
    @State private var showingCapture = false
    @State private var showingCompare = false
    @State private var selectedGroup: ProgressPhotoGroup?
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if photoService.groupedByDate.isEmpty {
                    emptyState
                } else {
                    compareButton
                    
                    ForEach(photoService.groupedByDate) { group in
                        dateGroupCard(group)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .background(
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
        )
        .navigationTitle("Progress Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCapture = true }) {
                    Image(systemName: "camera.fill")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCapture) {
            ProgressPhotoCaptureView()
        }
        .sheet(isPresented: $showingCompare) {
            ProgressPhotoCompareView()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            
            Text("No Progress Photos Yet")
                .font(.headline)
            
            Text("Take your first progress photo to start tracking your transformation.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showingCapture = true }) {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            .clipShape(Capsule())
                    )
            }
        }
        .padding(.vertical, 60)
    }
    
    private var compareButton: some View {
        Group {
            if photoService.groupedByDate.count >= 2 {
                Button(action: { showingCompare = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle.angled")
                        Text("Compare Photos")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                }
            }
        }
    }
    
    private func dateGroupCard(_ group: ProgressPhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.date, style: .date)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let weight = group.weight {
                    Text(String(format: "%.1f lbs", weight))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(group.photos, id: \.id) { photo in
                    photoThumbnail(photo)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.14) : Color.white)
        )
    }
    
    private func photoThumbnail(_ photo: ProgressPhoto) -> some View {
        Group {
            if let image = photoService.loadImage(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        Text(photo.type.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.5)))
                            .padding(Spacing.xxs),
                        alignment: .bottomLeading
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}

// MARK: - Compare View

struct ProgressPhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var photoService = ProgressPhotoService.shared
    
    @State private var leftIndex: Int = 0
    @State private var rightIndex: Int = 1
    @State private var selectedType: PhotoType = .front
    
    private var groups: [ProgressPhotoGroup] {
        photoService.groupedByDate
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Photo Type", selection: $selectedType) {
                    ForEach(PhotoType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.md)
                
                if groups.count >= 2 {
                    comparisonArea
                    
                    dataDelta
                    
                    dateSelectors
                } else {
                    VStack(spacing: 12) {
                        Text("Need at least 2 photo sessions to compare")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                }
                
                Spacer()
            }
            .padding(.top, 8)
            .background(
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var comparisonArea: some View {
        HStack(spacing: 4) {
            comparisonImage(for: leftIndex)
            comparisonImage(for: rightIndex)
        }
        .padding(.horizontal, Spacing.md)
    }
    
    private func comparisonImage(for groupIndex: Int) -> some View {
        Group {
            if groupIndex < groups.count,
               let photo = groups[groupIndex].photos.first(where: { $0.type == selectedType }),
               let image = photoService.loadImage(for: photo) {
                VStack(spacing: 4) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 350)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    Text(groups[groupIndex].date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 350)
                        .overlay(
                            Text("No \(selectedType.displayName) photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                    
                    if groupIndex < groups.count {
                        Text(groups[groupIndex].date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private var dataDelta: some View {
        Group {
            if leftIndex < groups.count && rightIndex < groups.count {
                let left = groups[leftIndex]
                let right = groups[rightIndex]
                
                if let lw = left.weight, let rw = right.weight {
                    let diff = lw - rw
                    HStack(spacing: 8) {
                        Image(systemName: diff < 0 ? "arrow.down.right" : diff > 0 ? "arrow.up.right" : "arrow.right")
                            .foregroundColor(diff < 0 ? .green : diff > 0 ? .red : .secondary)
                        Text(String(format: "%+.1f lbs", diff))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.cardBackground))
                }
            }
        }
    }
    
    private var dateSelectors: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("BEFORE")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                Picker("Before", selection: $leftIndex) {
                    ForEach(groups.indices, id: \.self) { i in
                        Text(groups[i].date, style: .date).tag(i)
                    }
                }
                .pickerStyle(.menu)
            }
            
            VStack(spacing: 4) {
                Text("AFTER")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                Picker("After", selection: $rightIndex) {
                    ForEach(groups.indices, id: \.self) { i in
                        Text(groups[i].date, style: .date).tag(i)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal, Spacing.md)
    }
}
