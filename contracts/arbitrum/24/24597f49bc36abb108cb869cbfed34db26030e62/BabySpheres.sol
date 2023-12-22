// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

import "./DefaultOperatorFilterer.sol";
import "./ERC721Enumerable.sol";
import "./ERC2981.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";

import "./IBabySpheres.sol";

contract BabySpheres is IBabySpheres, DefaultOperatorFilterer, ERC721Enumerable, ERC2981, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAXIMUM_SUPPLY = 700;
    uint96 public constant ROYALTY_PERCENTAGE = 1000;

    uint256 public mintEnablingTimestamp;
    uint256 public nextTokenId = 129;
    string public baseURI;

    EnumerableSet.AddressSet private _originalMinters;

    mapping(address => bool) public isPrivatePeriodAccount;
    mapping(address => bool) public isWhitelistPeriodAccount;
    mapping(address => bool) public minted;

    /// @param owner_ Collection owner.
    /// @param baseURI_ Base URI.
    constructor(address owner_, string memory baseURI_) ERC721("Baby Spheres", "Baby Sphere") {
        for (uint256 i = 1; i <= 128; ) {
            _safeMint(owner_, i);
            unchecked {
                i++;
            }
        }
        baseURI = baseURI_;
        _setDefaultRoyalty(owner_, ROYALTY_PERCENTAGE);
    }

    /// @inheritdoc IBabySpheres
    function enableMint() external onlyOwner {
        if (mintEnablingTimestamp != 0) {
            revert MintAlreadyEnabled();
        }
        mintEnablingTimestamp = block.timestamp;
        emit MintEnabled(block.timestamp);
    }

    /// @inheritdoc IBabySpheres
    function updateBaseURI(string calldata baseURI_) external onlyOwner {
        emit BaseURIUpdated(baseURI, baseURI_);
        baseURI = baseURI_;
    }

    /// @inheritdoc IBabySpheres
    function addPrivatePeriodAccounts(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; ) {
            isPrivatePeriodAccount[accounts_[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBabySpheres
    function removePrivatePeriodAccounts(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; ) {
            delete isPrivatePeriodAccount[accounts_[i]];
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBabySpheres
    function addWhitelistPeriodAccounts(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; ) {
            isWhitelistPeriodAccount[accounts_[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBabySpheres
    function removeWhitelistPeriodAccounts(address[] calldata accounts_) external onlyOwner {
        for (uint256 i = 0; i < accounts_.length; ) {
            delete isWhitelistPeriodAccount[accounts_[i]];
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IBabySpheres
    function mint() external {
        if (totalSupply() == MAXIMUM_SUPPLY) {
            revert MaximumSupplyExceeded();
        }
        uint256 m_mintEnablingTimestamp = mintEnablingTimestamp;
        if (m_mintEnablingTimestamp == 0) {
            revert ForbiddenToMintTokens();
        }
        uint256 difference;
        unchecked {
            difference = block.timestamp - m_mintEnablingTimestamp;
        }
        if (difference <= 1 hours) {
            if (!isPrivatePeriodAccount[msg.sender] || minted[msg.sender]) {
                revert ForbiddenToMintTokens();
            }
        } else if (difference > 1 hours && difference <= 2 hours) {
            if (
                !isPrivatePeriodAccount[msg.sender] ||
                !isWhitelistPeriodAccount[msg.sender] ||  
                minted[msg.sender]
            ) {
                revert ForbiddenToMintTokens();
            }
        } else {
            if (minted[msg.sender]) {
                revert ForbiddenToMintTokens();
            }
        }
        _safeMint(msg.sender, nextTokenId);
        minted[msg.sender] = true;
        _originalMinters.add(msg.sender);
        unchecked {
            nextTokenId++;
        }
    }

    /// @inheritdoc IBabySpheres
    function isOriginalMinter(address account_) external view returns (bool) {
        return _originalMinters.contains(account_);
    }

    /// @inheritdoc IBabySpheres
    function originalMintersLength() external view returns (uint256) {
        return _originalMinters.length();
    }

    /// @inheritdoc IBabySpheres
    function originalMinterAt(uint256 index_) external view returns (address) {
        return _originalMinters.at(index_);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId_
    )
        public
        view
        override(ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId_);
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
