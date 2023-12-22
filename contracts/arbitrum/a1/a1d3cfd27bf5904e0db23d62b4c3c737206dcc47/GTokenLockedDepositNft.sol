// SPDX-License-Identifier: MIT
import "./ERC721Enumerable.sol";
import "./interfaces_IERC20Metadata.sol";
import "./IERC4626.sol";

import "./IGTokenLockedDepositNftDesign.sol";

pragma solidity 0.8.17;

contract GTokenLockedDepositNft is ERC721Enumerable{
    address public immutable gToken;
    IGTokenLockedDepositNftDesign public design;

    uint8 public designDecimals;

    event DesignUpdated(IGTokenLockedDepositNftDesign newValue);
    event DesignDecimalsUpdated(uint8 newValue);

    constructor(
        string memory name,
        string memory symbol,
        address _gToken,
        IGTokenLockedDepositNftDesign _design,
        uint8 _designDecimals
    ) ERC721(name, symbol){
        gToken = _gToken;
        design = _design;
        designDecimals = _designDecimals;
    }

    modifier onlyGToken{
        require(msg.sender == gToken, "ONLY_GTOKEN");
        _;
    }

    modifier onlyGTokenManager{
        require(msg.sender == IGToken(gToken).manager(), "ONLY_MANAGER");
        _;
    }

    function updateDesign(IGTokenLockedDepositNftDesign newValue) external onlyGTokenManager{
        design = newValue;
        emit DesignUpdated(newValue);
    }

    function updateDesignDecimals(uint8 newValue) external onlyGTokenManager{
        designDecimals = newValue;
        emit DesignDecimalsUpdated(newValue);
    }

    function mint(address to, uint tokenId) external onlyGToken{
        _safeMint(to, tokenId);
    }

    function burn(uint tokenId) external onlyGToken{
        _burn(tokenId);
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        return design.buildTokenURI(
            tokenId,
            IGToken(gToken).getLockedDeposit(tokenId),
            IERC20Metadata(gToken).symbol(),
            IERC20Metadata(IERC4626(gToken).asset()).symbol(),
            IERC20Metadata(gToken).decimals(),
            designDecimals
        );
    }
}
