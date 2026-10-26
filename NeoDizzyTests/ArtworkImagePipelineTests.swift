import Nuke
import Testing
import UIKit
@testable import NeoDizzy

@MainActor
struct ArtworkImagePipelineTests {
    @Test(arguments: [CGFloat(2), CGFloat(3)])
    func rowArtworkPreservesDisplayResolutionWithSmallerDecodedBitmaps(displayScale: CGFloat) throws {
        let data = try artworkData(size: CGSize(width: 1_024, height: 1_024))
        let request = try #require(ArtworkImagePipeline.request(
            for: URL(string: "https://example.com/cover.png"),
            size: CGSize(width: 44, height: 44), displayScale: displayScale))
        let image = try #require(request.thumbnail?.makeThumbnail(with: data)?.cgImage)
        let previous = try #require(ImageRequest.ThumbnailOptions(
            size: CGSize(width: 128 * displayScale, height: 128 * displayScale), unit: .pixels
        ).makeThumbnail(with: data)?.cgImage)

        #expect(CGFloat(image.width) >= 44 * displayScale)
        #expect(CGFloat(image.width) < 44 * displayScale + 64)
        #expect(image.width == image.height)
        #expect(image.bytesPerRow * image.height <= previous.bytesPerRow * previous.height / 4)
    }

    @Test func nearbyLayoutsReuseDecodedImagesWithoutMixingSizeModeOrSource() throws {
        let url = try #require(URL(string: "https://example.com/cover.png"))
        func request(width: CGFloat, scale: CGFloat = 3,
                     mode: ImageProcessingOptions.ContentMode = .aspectFill,
                     source: URL? = nil) throws -> ImageRequest {
            try #require(ArtworkImagePipeline.request(
                for: source ?? url, size: CGSize(width: width, height: width),
                displayScale: scale, contentMode: mode))
        }
        let pipeline = ImagePipeline { $0.imageCache = ImageCache(costLimit: 4 * 1_024 * 1_024) }
        let initial = try request(width: 44)
        let image = try #require(initial.thumbnail?.makeThumbnail(with: artworkData(size: CGSize(width: 512, height: 512))))
        pipeline.cache[initial] = ImageContainer(image: image)

        #expect(pipeline.cache[try request(width: 48)]?.image === image)
        #expect(pipeline.cache[try request(width: 65)] == nil)
        #expect(pipeline.cache[try request(width: 44, scale: 2)] == nil)
        #expect(pipeline.cache[try request(width: 44, mode: .aspectFit)] == nil)
        #expect(pipeline.cache[try request(width: 44, source: URL(string: "https://example.com/another.png"))] == nil)
    }

    @Test func rectangularImagesRetainFitAndFillBehavior() throws {
        let data = try artworkData(size: CGSize(width: 1_024, height: 512))
        let url = try #require(URL(string: "https://example.com/wide.png"))
        let fill = try #require(ArtworkImagePipeline.request(
            for: url, size: CGSize(width: 44, height: 44), displayScale: 3,
            contentMode: .aspectFill)?.thumbnail?.makeThumbnail(with: data)?.cgImage)
        let fit = try #require(ArtworkImagePipeline.request(
            for: url, size: CGSize(width: 44, height: 44), displayScale: 3,
            contentMode: .aspectFit)?.thumbnail?.makeThumbnail(with: data)?.cgImage)

        #expect(fill.width == 384 && fill.height == 192)
        #expect(fit.width == 192 && fit.height == 96)
    }

    @Test func invalidLayoutDoesNotStartARequestAndExplicitDecodeSizeStaysExact() throws {
        let url = try #require(URL(string: "https://example.com/cover.png"))
        for size in [CGSize.zero, CGSize(width: -1, height: 44),
                     CGSize(width: CGFloat.infinity, height: 44), CGSize(width: CGFloat.nan, height: 44)] {
            #expect(ArtworkImagePipeline.request(for: url, size: size, displayScale: 3) == nil)
        }
        #expect(ArtworkImagePipeline.request(for: url, size: CGSize(width: 44, height: 44), displayScale: 0) == nil)
        #expect(ArtworkImagePipeline.request(for: nil, size: CGSize(width: 44, height: 44), displayScale: 3) == nil)
        let request = try #require(ArtworkImagePipeline.request(
            for: url, size: .zero, displayScale: 3, decodeSize: CGSize(width: 50, height: 50)))
        let image = try #require(request.thumbnail?.makeThumbnail(with: artworkData(size: CGSize(width: 512, height: 512)))?.cgImage)
        #expect(image.width == 150 && image.height == 150)
    }

    private func artworkData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try #require(image.pngData())
    }
}
