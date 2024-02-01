// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/// @title Archive of Elements of the ScapeLand
/// @author jalil.eth, akuti.eth | scapes.eth
interface IScapesArchive {
    /// @title Metadata for an archived element from ScapeLand
    /// @param format The format in which the data is stored (PNG/SVG/...)
    /// @param collectionId Documented off chain
    /// @param isObject False implies background
    /// @param width The true pixel width of the element
    /// @param height The true pixel height of the element
    /// @param x The default offset from the left
    /// @param y The default offset from the top
    /// @param zIndex Default z-index of the element
    /// @param canFlipX The element can be flipped horizontally
    /// @param canFlipY Can be flipped vertically without obscuring content
    /// @param seamlessX The element can be tiled horizontally
    /// @param seamlessY The element can be tiled vertically
    /// @param addedAt Automatically freezes after 1 week
    struct ElementMetadata {
        uint8 format;
        uint16 collectionId;
        bool isObject;
        uint16 width;
        uint16 height;
        int16 x;
        int16 y;
        uint8 zIndex;
        bool canFlipX;
        bool canFlipY;
        bool seamlessX;
        bool seamlessY;
        uint64 addedAt;
    }

    /// @title An archived element from ScapeLand
    /// @param data The raw data (normally the image)
    /// @param metadata The elements' configuration data
    struct Element {
        bytes data;
        ElementMetadata metadata;
    }

    /// @notice Get the bare data for an archived item
    /// @param category The category of the element
    /// @param name The identifying name of the element
    function getElement(string memory category, string memory name)
        external
        view
        returns (Element memory item);
}

