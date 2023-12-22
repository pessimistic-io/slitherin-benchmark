// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC721 } from "./ERC721.sol";
import { Base64 } from "./Base64.sol";
import { Strings } from "./Strings.sol";
import { ISupaBeta } from "./ISupaBeta.sol";

contract SupaBeta is ERC721 {
    using Strings for address;
    using Strings for string;
    using Strings for uint256;

    /// @notice Thrown on transfer if the tokens are locked.
    error Locked();
    /// @notice Thrown on mint if the caller is not a minter.
    error OnlyMinter();
    /// @notice Thrown when the caller is not the owner.
    error OnlyOwner();

    modifier onlyMinter() {
        if (!hasMinterRole[msg.sender]) revert OnlyMinter();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != ISupaBeta(address(this)).owner()) revert OnlyOwner();
        _;
    }

    /// @notice Whether the tokens are transferable or not.
    bool public isTransferable;

    /// @notice Whether the tokens are transferable or not.
    /// @dev This is a mapping to support multiple minters.
    mapping(address user => bool isMinter) public hasMinterRole;

    address private _proxy;
    uint256 private _tokenCounter;

    constructor() ERC721("Supa Beta Access", "SUPA_BETA") {}

    /// @notice Mints a new token.
    /// @dev Only callable by a minter.
    /// @param to The address of the token recipient.
    function mint(address to) external onlyMinter {
        _safeMint(to, _tokenCounter++);
    }

    /// @notice Mints new tokens to an array of addresses.
    /// @dev Only callable by a minter.
    /// @param to The addresses of the token recipients.
    function batchMint(address[] calldata to) external onlyMinter {
        for (uint256 i = 0; i < to.length; i++) {
            _safeMint(to[i], _tokenCounter++);
        }
    }

    /// @notice Mints a new token.
    /// @dev Only callable by the owner.
    /// @param user The address of the minter.
    /// @param isMinter Whether the user is a minter or not.
    function setMinter(address user, bool isMinter) external onlyOwner {
        hasMinterRole[user] = isMinter;
    }

    /// @notice Sets whether the tokens are transferable or not.
    /// @dev Only callable by the owner.
    function setIsTransferable(bool _isTransferable) external onlyOwner {
        isTransferable = _isTransferable;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory color = generateAccentColor(ownerOf(tokenId), tokenId);
        bytes memory image = abi.encodePacked(
            "data:image/svg+xml;base64,",
            Base64.encode(
                bytes(
                    abi.encodePacked(
                        '<svg width="388" height="134" viewBox="0 0 388 134" fill="none" xmlns="http://www.w3.org/2000/svg">',
                        '<g clip-path="url(#clip0_2118_5536)" fill="', color, '">',
                        '<path id="logo-top" d="M53.2851 1.77712C57.3978 -0.592374 62.4646 -0.592374 66.5777 1.77712L113.216 28.6461C117.329 31.0156 119.862 35.3942 119.862 40.1332V56.11L93.3853 56.1174L69.8772 56.1253C68.8285 56.1253 67.9782 55.2768 67.9782 54.2304V29.7726C67.9782 28.8816 66.8572 28.4833 66.293 29.1739L26.4812 77.8972L0 51.2766V40.1332C0 35.3942 2.53361 31.0156 6.64627 28.6461L53.2851 1.77712Z"/>',
                        '<path id="logo-bottom" d="M26.4812 77.897L49.9935 77.9192C51.0418 77.9197 51.8911 78.7681 51.8911 79.8141V104.252C51.8911 105.144 53.0121 105.542 53.5763 104.851L93.3853 56.1172L119.862 82.723V93.871C119.862 98.61 117.329 102.989 113.216 105.358L66.5777 132.227C62.4646 134.597 57.3978 134.597 53.2851 132.227L6.64627 105.358C2.53361 102.989 0 98.61 0 93.871V77.8965L26.4812 77.897Z"/>',
                        '<path id="supa-s" d="M150.583 92.8604C155.105 96.174 161.322 97.8309 169.236 97.8309C174.323 97.8309 178.739 97.0553 182.483 95.5043C186.228 93.9532 189.125 91.8028 191.174 89.0532C193.294 86.2331 194.353 82.9194 194.353 79.1122C194.353 73.9655 192.41 69.8763 188.524 66.8447C184.709 63.813 179.41 61.9447 172.627 61.2396L167.54 60.7109C164.431 60.3584 162.17 59.6886 160.757 58.7015C159.415 57.7145 158.743 56.3044 158.743 54.4713C158.743 52.5677 159.591 51.0167 161.287 49.8181C162.983 48.6195 165.385 48.0203 168.494 48.0203C171.956 48.0203 174.605 48.7253 176.442 50.1354C178.279 51.5454 179.269 53.2375 179.41 55.2116H192.658C192.446 49.2188 190.15 44.6714 185.769 41.5692C181.388 38.4671 175.665 36.916 168.6 36.916C164.078 36.916 160.051 37.621 156.518 39.0311C153.056 40.3707 150.335 42.38 148.357 45.0591C146.379 47.7383 145.39 51.0519 145.39 55.0001C145.39 59.9353 147.121 63.8835 150.583 66.8447C154.045 69.8058 158.991 71.6389 165.42 72.3439L170.507 72.8727C174.323 73.2252 177.008 73.9655 178.562 75.0935C180.187 76.2216 181 77.7374 181 79.641C181 81.8266 179.94 83.5539 177.82 84.823C175.771 86.0921 172.98 86.7266 169.448 86.7266C165.208 86.7266 162.1 85.9158 160.121 84.2942C158.143 82.6726 157.048 80.8748 156.836 78.9007H143.588C143.8 84.823 146.132 89.4762 150.583 92.8604Z"/>',
                        '<path id="supa-u" d="M200.883 68.918V40.2861H214.713V68.918C214.713 76.802 221.118 83.1933 229.018 83.1933C236.919 83.1933 243.324 76.802 243.324 68.918V40.2861H257.154V68.918C257.154 84.4236 244.557 96.9933 229.018 96.9933C213.48 96.9933 200.883 84.4236 200.883 68.918Z"/>',
                        '<path id="supa-p" fill-rule="evenodd" clip-rule="evenodd" d="M294.943 38.4336C288.248 38.4336 282.451 39.7365 277.825 42.6906L277.444 42.9337V40.533H265.66V80.952H265.681V114.398H278.111V90.9978L279.482 91.8617C283.956 94.6809 289.258 96.3128 294.943 96.3128C310.961 96.3128 323.945 83.3562 323.945 67.3734C323.945 51.3902 310.961 38.4336 294.943 38.4336ZM278.372 67.3734C278.372 58.2408 285.791 50.8371 294.943 50.8371C304.096 50.8371 311.515 58.2408 311.515 67.3734C311.515 76.506 304.096 83.9093 294.943 83.9093C285.791 83.9093 278.372 76.506 278.372 67.3734Z"/>',
                        '<path id="supa-a" fill-rule="evenodd" clip-rule="evenodd" d="M387.7 40.533V80.952H387.679V95.6529H375.249V90.9978L373.878 91.8617C369.403 94.6809 364.102 96.3128 358.416 96.3128C342.399 96.3128 329.414 83.3562 329.414 67.3734C329.414 51.3902 342.399 38.4336 358.416 38.4336C365.096 38.4336 370.895 40.2111 375.527 43.4208L375.916 43.6899V40.533H387.7ZM358.416 50.8371C349.264 50.8371 341.845 58.2408 341.845 67.3734C341.845 76.506 349.264 83.9093 358.416 83.9093C367.568 83.9093 374.988 76.506 374.988 67.3734C374.988 58.2408 367.568 50.8371 358.416 50.8371Z"/>',
                        '</g>',
                        '<defs>',
                        '<clipPath id="clip0_2118_5536">',
                        '<rect width="388" height="134" fill="white"/>',
                        '</clipPath>',
                        '</defs>',
                        '</svg>'
                    )
                )
            )
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"Supa Beta Access", "image":"',
                            image,
                            '", "description": "This NFT gives access to the Supa Beta."}'
                        )
                    )
                )
            )
        );
    }

    function _transfer(address from, address to, uint256 tokenId) internal override {
        if (!isTransferable) revert Locked();
        super._transfer(from, to, tokenId);
    }

    /// @notice Generates a pseudo-random HSL color by hashing together the `chainid`, the `sablier` address,
    /// and the `streamId`. This will be used as the accent color for the SVG.
    function generateAccentColor(address owner, uint256 streamId) internal view returns (string memory) {
        // The chain id is part of the hash so that the generated color is different across chains.
        uint256 chainId = block.chainid;

        // Hash the parameters to generate a pseudo-random bit field, which will be used as entropy.
        // | Hue     | Saturation | Lightness | -> Roles
        // | [31:16] | [15:8]     | [7:0]     | -> Bit positions
        uint32 bitField = uint32(uint256(keccak256(abi.encodePacked(chainId, owner, streamId))));

        unchecked {
        // The hue is a degree on a color wheel, so its range is [0, 360).
        // Shifting 16 bits to the right means using the bits at positions [31:16].
            uint256 hue = (bitField >> 16) % 360;

        // The saturation is a percentage where 0% is grayscale and 100%, but here the range is bounded to [20,100]
        // to make the colors more lively.
        // Shifting 8 bits to the right and applying an 8-bit mask means using the bits at positions [15:8].
            uint256 saturation = ((bitField >> 8) & 0xFF) % 80 + 20;

        // The lightness is typically a percentage between 0% (black) and 100% (white), but here the range
        // is bounded to [30,100] to avoid dark colors.
        // Applying an 8-bit mask means using the bits at positions [7:0].
            uint256 lightness = (bitField & 0xFF) % 70 + 30;

        // Finally, concatenate the HSL values to form an SVG color string.
            return string.concat("hsl(", hue.toString(), ",", saturation.toString(), "%,", lightness.toString(), "%)");
        }
    }

}
