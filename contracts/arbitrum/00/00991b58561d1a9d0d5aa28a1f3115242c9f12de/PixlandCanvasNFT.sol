pragma solidity 0.8.20;

import "./Ownable.sol";
import "./ERC721.sol";

import {IERC721Receiver} from "./IERC721Receiver.sol";

import "./IERC20.sol";

import "./AbstractNFT.sol";

// This contract inherits all functionality from AbstractNFT and implements arbitrary price for pixels.

contract PixlandCanvasNFT is AbstractNFT {
    uint16 internal priceFeeBasisPoints;

    mapping(address => uint256) private userValues;

    uint8[256] private baseURIBytes;
    uint16 private baseURILength;

    uint8[128] private extensionBytes;
    uint16 private extensionLength;

    constructor(
        string memory __name,
        address _token,
        address _dev,
        uint256 _mintFee,
        uint16 _priceFeeBasisPoints,
        uint16 _acquisitionTaxBasisPoints
    )
        public
        AbstractNFT(__name, _token, _dev, _mintFee, _acquisitionTaxBasisPoints)
    {
        priceFeeBasisPoints = _priceFeeBasisPoints;

        string memory newBaseURI = "https://pixland.place/tokenMetadata/";
        setBaseURI(newBaseURI);

        string memory extension = ".json";
        setExtension(extension);
    }

    function getChainId() public view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }

        return chainId;
    }

    // Returns the string value of baseURI
    function getBaseURI() public view returns (string memory) {
        bytes memory tmp = new bytes(512);
        for (uint8 i = 0; i < 16; i++) {
            assembly {
                let offset := mul(0x20, i)
                mstore(
                    add(tmp, add(0x20, offset)),
                    sload(add(baseURIBytes.slot, offset))
                )
            }
        }

        return string(tmp);
    }

    // Changes the baseURI
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        require(bytes(newBaseURI).length < 512, "newBaseURI too long");
        baseURILength = uint16(bytes(newBaseURI).length);

        for (uint8 i = 0; i < 1 + baseURILength / 32; i++) {
            assembly {
                let offset := mul(0x20, i)
                sstore(
                    add(baseURIBytes.slot, offset),
                    mload(add(newBaseURI, add(0x20, offset)))
                )
            }
        }
    }

    // Works
    function getBaseURILength() public view returns (uint16) {
        return baseURILength;
    }

    // Returns the string value of Extension
    function getExtension() public view returns (string memory) {
        bytes memory tmp = new bytes(512);
        for (uint8 i = 0; i < 16; i++) {
            assembly {
                let offset := mul(0x20, i)
                mstore(
                    add(tmp, add(0x20, offset)),
                    sload(add(extensionBytes.slot, offset))
                )
            }
        }

        return string(tmp);
    }

    // Changes the extension
    function setExtension(string memory newExtension) public onlyOwner {
        require(bytes(newExtension).length < 512, "newExtension too long");
        extensionLength = uint16(bytes(newExtension).length);

        for (uint8 i = 0; i < 1 + extensionLength / 32; i++) {
            assembly {
                let offset := mul(0x20, i)
                sstore(
                    add(extensionBytes.slot, offset),
                    mload(add(newExtension, add(0x20, offset)))
                )
            }
        }
    }

    // Works
    function getExtensionLength() public view returns (uint16) {
        return extensionLength;
    }

    // Convert hex values to ASCII char e.g. 9 -> '9', a -> 'a'
    function toc(uint8 i) public pure returns (uint8) {
        if (i <= 9) {
            return i + 48;
        } else {
            return i + 87;
        }
    }

    // Converts an address (20 bytes) to the corresponding ASCII string starting with '0x' (42 bytes)
    function addressToAsciiBytes(address x) public pure returns (bytes memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i + 2] = bytes1(toc(uint8(hi)));
            s[2 * i + 3] = bytes1(toc(uint8(lo)));
        }
        return s;
    }

    // Converts an uint256 (32 bytes) to the corresponding (DECIMAL) ASCII string
    function uint256ToString(
        uint256 num
    ) public pure returns (bytes memory, uint16) {
        uint256 temp = num;
        uint16 digits;

        while (temp > 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        if (num == 0) {
            buffer[0] = bytes1(uint8(48 + (num % 10)));
            return (buffer, 1);
        }

        uint16 k = digits;
        while (num > 0) {
            buffer[--k] = bytes1(uint8(48 + (num % 10)));
            num /= 10;
        }

        return (buffer, digits);
    }

    // Computes bytes of tokenURI quite autistically
    // tokenURI = <baseUR><chainId>_<address>_<tokenId><extension>
    // E.g.: https://pixland.place/5_0x2db4284554817d119797c7845de13aafb5befaec_11223344556677.json
    function tokenURIBytes(
        uint256 tokenId
    ) internal view returns (bytes memory) {
        bytes memory tmp = new bytes(512);

        // Load baseURI into tmp
        for (uint8 i = 0; i < 16; i++) {
            assembly {
                let offset := mul(0x20, i)
                mstore(
                    add(tmp, add(0x20, offset)),
                    sload(add(baseURIBytes.slot, offset))
                )
            }
        }

        (bytes memory chainIdBytes, uint16 numDigits) = uint256ToString(
            getChainId()
        );

        bytes memory thisAddress = addressToAsciiBytes(address(this));

        (bytes memory tokenIdBytes, uint16 tokenIdDigits) = uint256ToString(
            tokenId
        );

        uint16 tokenURILength = numDigits +
            1 +
            42 +
            1 +
            tokenIdDigits +
            1 +
            extensionLength;

        bytes memory concatenated = new bytes(tokenURILength);

        for (uint16 k = 0; k < numDigits; k++) {
            concatenated[k] = chainIdBytes[k];
        }

        concatenated[numDigits] = 0x5f;

        for (uint16 k = 0; k < 42; k++) {
            concatenated[numDigits + k + 1] = thisAddress[k];
        }

        concatenated[numDigits + 1 + 42] = 0x5f;

        for (uint16 k = 0; k < tokenIdDigits; k++) {
            concatenated[numDigits + 1 + 42 + k + 1] = tokenIdBytes[k];
        }

        bytes memory tmpExt = new bytes(512);
        for (uint8 i = 0; i < 16; i++) {
            assembly {
                let offset := mul(0x20, i)
                mstore(
                    add(tmpExt, add(0x20, offset)),
                    sload(add(extensionBytes.slot, offset))
                )
            }
        }

        for (uint16 k = 0; k < extensionLength; k++) {
            concatenated[numDigits + 1 + 42 + tokenIdDigits + k + 1] = tmpExt[
                k
            ];
        }

        // Load chainid after base URI
        for (uint8 i = 0; i < 1 + tokenURILength / 32; i++) {
            assembly {
                let offset := mul(0x20, i)
                let baseURIOffset := sload(baseURILength.slot)
                mstore(
                    add(add(tmp, 0x20), add(baseURIOffset, offset)),
                    mload(add(concatenated, add(0x20, offset)))
                )
            }
        }

        return tmp;
    }

    // Actual tokenURI function
    // The server will compute the json metadata based on the URI itself.
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        bytes memory urib = tokenURIBytes(tokenId);
        return string(urib);
    }

    function getPriceFeeBasisPoints() public view returns (uint16) {
        return priceFeeBasisPoints;
    }

    function changePriceFeeBasisPoints(uint16 _newbp) public onlyOwner {
        priceFeeBasisPoints = _newbp;
    }

    function valueOf(address user) public view returns (uint256) {
        return userValues[user];
    }

    function unsafeTransferPixel(uint256 tokenId, address to) public override {
        require(_ownerOf(tokenId) == msg.sender);

        // Change original owners value
        userValues[_ownerOf(tokenId)] -= prices[tokenId];

        // Change users value
        userValues[to] += prices[tokenId];

        // transfer
        _transfer(msg.sender, to, tokenId);
    }

    function unsafeTransferPixelsBulk(
        uint256[] calldata tokenIds,
        address to
    ) public override {
        uint256 tokenValue = 0;
        // WARN: This unbounded for loop is an anti-pattern
        for (uint i = 0; i < tokenIds.length; i++) {
            require(_ownerOf(tokenIds[i]) == msg.sender);
            tokenValue += prices[tokenIds[i]];
            // transfer
            _transfer(msg.sender, to, tokenIds[i]);
        }

        // Change original owners value
        userValues[msg.sender] -= tokenValue;

        // Change users value
        userValues[to] += tokenValue;
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );

        // Change original owners value
        userValues[_ownerOf(tokenId)] -= prices[tokenId];

        // Change users value
        userValues[to] += prices[tokenId];

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal override {
        // Change original owners value
        userValues[_ownerOf(tokenId)] -= prices[tokenId];

        // Change users value
        userValues[to] += prices[tokenId];

        _transfer(from, to, tokenId);
        require(
            __checkOnERC721Received(from, to, tokenId, data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function __checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * Minting functions
     */
    function mintPixel(uint256 id, uint24 c) public pure override {
        revert();
    }

    function mintPixelBulk(
        uint256[] calldata tokenIds,
        uint24[] calldata c
    ) public pure override {
        revert();
    }

    /*
     * Full committers
     */
    function commit(
        uint256 tokenId,
        uint24 c,
        uint256 newPrice
    ) public override {
        uint256 totalFee = 0;

        if (_exists(tokenId)) {
            if (_ownerOf(tokenId) == msg.sender) {
                pixelColor[tokenId] = c;

                // Change users value bases on price difference
                // Change can be negative
                if (newPrice > prices[tokenId]) {
                    userValues[msg.sender] += newPrice - prices[tokenId];

                    // Apply price based fee
                    totalFee +=
                        ((newPrice - prices[tokenId]) * priceFeeBasisPoints) /
                        10000;
                } else {
                    userValues[msg.sender] -= prices[tokenId] - newPrice;
                }

                prices[tokenId] = newPrice;
            } else {
                // Change original owners value
                userValues[_ownerOf(tokenId)] -= prices[tokenId];

                // Change users value
                userValues[msg.sender] += newPrice;

                if (newPrice > prices[tokenId]) {
                    // Apply price based fee
                    totalFee +=
                        ((newPrice - prices[tokenId]) * priceFeeBasisPoints) /
                        10000;
                }

                // Pay pixel owner BEFORE CALLING _transfer !!!!
                IERC20(token).transferFrom(
                    msg.sender,
                    _ownerOf(tokenId),
                    (prices[tokenId] * (10000 - acquisitionTaxBasisPoints)) /
                        10000
                );

                // Acquire token
                _transfer(_ownerOf(tokenId), msg.sender, tokenId);

                // Transaction tax
                totalFee +=
                    (prices[tokenId] * (acquisitionTaxBasisPoints)) /
                    10000;

                // Set color
                pixelColor[tokenId] = c;

                // Set new price
                prices[tokenId] = newPrice;
            }
        } else {
            _mint(msg.sender, tokenId);

            idmap[idcount] = tokenId;
            idcount = idcount + 1;

            // Set color
            pixelColor[tokenId] = c;

            // Increase users value
            userValues[msg.sender] += newPrice;

            // Apply price based fee (price[tokenId] = 0)
            totalFee += mintFee + (newPrice * priceFeeBasisPoints) / 10000;

            // Set new price
            prices[tokenId] = newPrice;
        }

        IERC20(token).transferFrom(msg.sender, dev, totalFee);
    }

    /*
     * Full committers
     */
    function commitBulk(
        uint256[] calldata tokenIds,
        uint24[] calldata cs,
        uint256[] calldata newPrices
    ) public override {
        uint256 totalFee = 0;

        // WARN: This unbounded for loop is an anti-pattern
        for (uint i = 0; i < tokenIds.length; i++) {
            if (_exists(tokenIds[i])) {
                if (_ownerOf(tokenIds[i]) == msg.sender) {
                    pixelColor[tokenIds[i]] = cs[i];

                    // Change users value bases on price difference
                    // Change can be negative
                    if (newPrices[i] > prices[tokenIds[i]]) {
                        userValues[msg.sender] +=
                            newPrices[i] -
                            prices[tokenIds[i]];

                        // Apply price based fee
                        totalFee +=
                            ((newPrices[i] - prices[tokenIds[i]]) *
                                priceFeeBasisPoints) /
                            10000;
                    } else {
                        userValues[msg.sender] -=
                            prices[tokenIds[i]] -
                            newPrices[i];
                    }

                    prices[tokenIds[i]] = newPrices[i];
                } else {
                    // Change original owners value
                    userValues[_ownerOf(tokenIds[i])] -= prices[tokenIds[i]];

                    // Change users value
                    userValues[msg.sender] += newPrices[i];

                    if (newPrices[i] > prices[tokenIds[i]]) {
                        // Apply price based fee
                        totalFee +=
                            ((newPrices[i] - prices[tokenIds[i]]) *
                                priceFeeBasisPoints) /
                            10000;
                    }

                    // Pay pixel owner BEFORE CALLING _transfer !!!!!!
                    IERC20(token).transferFrom(
                        msg.sender,
                        _ownerOf(tokenIds[i]),
                        (prices[tokenIds[i]] *
                            (10000 - acquisitionTaxBasisPoints)) / 10000
                    );

                    // Acquire token
                    _transfer(_ownerOf(tokenIds[i]), msg.sender, tokenIds[i]);

                    // Transaction fee
                    totalFee +=
                        (prices[tokenIds[i]] * (acquisitionTaxBasisPoints)) /
                        10000;

                    // repaint
                    pixelColor[tokenIds[i]] = cs[i];

                    // Set new price
                    prices[tokenIds[i]] = newPrices[i];
                }
            } else {
                _mint(msg.sender, tokenIds[i]);

                idmap[idcount] = tokenIds[i];
                idcount = idcount + 1;

                pixelColor[tokenIds[i]] = cs[i];

                // Apply price based fee (prices[tokenIds[i]] = 0)
                totalFee +=
                    mintFee +
                    (newPrices[i] * priceFeeBasisPoints) /
                    10000;

                // Change users value
                userValues[msg.sender] += newPrices[i];

                // Set new price
                prices[tokenIds[i]] = newPrices[i];
            }
        }

        IERC20(token).transferFrom(msg.sender, dev, totalFee);
    }

    function getCommitFeeTaxPriceAndCounts(
        uint256 tokenId,
        uint256 newPrice,
        address beneficiary
    ) public view override returns (uint256[3] memory, uint16[2] memory) {
        // Returns: fee, tax, total price, mint count, overwrite count
        // Fee + Tax + Price should be equal to the amount paid by the committer.
        // Fee + Tax is received by devs, and price is received by pixel owners.

        uint256[3] memory _feeTaxPrice;
        _feeTaxPrice[0] = 0;
        _feeTaxPrice[1] = 0;
        _feeTaxPrice[2] = 0;

        uint16[2] memory _mcoc;
        _mcoc[0] = 0;
        _mcoc[1] = 0;

        if (_exists(tokenId)) {
            if (_ownerOf(tokenId) == beneficiary) {
                // nothing

                if (newPrice > prices[tokenId]) {
                    _feeTaxPrice[0] +=
                        ((newPrice - prices[tokenId]) * priceFeeBasisPoints) /
                        10000;
                }
            } else {
                _feeTaxPrice[2] =
                    (prices[tokenId] * (10000 - acquisitionTaxBasisPoints)) /
                    10000;

                if (newPrice > prices[tokenId]) {
                    _feeTaxPrice[0] +=
                        ((newPrice - prices[tokenId]) * priceFeeBasisPoints) /
                        10000;
                }

                _feeTaxPrice[1] =
                    (prices[tokenId] * (acquisitionTaxBasisPoints)) /
                    10000;

                _mcoc[1]++;
            }
        } else {
            _feeTaxPrice[0] +=
                mintFee +
                (newPrice * priceFeeBasisPoints) /
                10000;
            _mcoc[0]++;
        }

        return (_feeTaxPrice, _mcoc);
    }

    function getCommitBulkFeeTaxPriceAndCounts(
        uint256[] calldata tokenIds,
        uint256[] calldata newPrices,
        address beneficiary
    ) public view override returns (uint256[3] memory, uint16[2] memory) {
        // Returns: fee, tax, total price, mint count, overwrite count
        // Fee + Tax + Price should be equal to the amount paid by the committer.
        // Fee + Tax is received by devs, and price is received by pixel owners.

        uint256[3] memory _feeTaxPrice;
        _feeTaxPrice[0] = 0;
        _feeTaxPrice[1] = 0;
        _feeTaxPrice[2] = 0;

        uint16[2] memory _mcoc;
        _mcoc[0] = 0;
        _mcoc[1] = 0;

        // WARN: This unbounded for loop is an anti-pattern
        for (uint i = 0; i < tokenIds.length; i++) {
            if (_exists(tokenIds[i])) {
                if (_ownerOf(tokenIds[i]) == beneficiary) {
                    if (newPrices[i] > prices[tokenIds[i]]) {
                        _feeTaxPrice[0] +=
                            ((newPrices[i] - prices[tokenIds[i]]) *
                                priceFeeBasisPoints) /
                            10000;
                    }
                } else {
                    _feeTaxPrice[2] +=
                        (prices[tokenIds[i]] *
                            (10000 - acquisitionTaxBasisPoints)) /
                        10000;

                    if (newPrices[i] > prices[tokenIds[i]]) {
                        _feeTaxPrice[0] +=
                            ((newPrices[i] - prices[tokenIds[i]]) *
                                priceFeeBasisPoints) /
                            10000;
                    }

                    _feeTaxPrice[1] +=
                        (prices[tokenIds[i]] * (acquisitionTaxBasisPoints)) /
                        10000;

                    _mcoc[1]++;
                }
            } else {
                _feeTaxPrice[0] +=
                    mintFee +
                    (newPrices[i] * priceFeeBasisPoints) /
                    10000;
                _mcoc[0]++;
            }
        }

        return (_feeTaxPrice, _mcoc);
    }
}

