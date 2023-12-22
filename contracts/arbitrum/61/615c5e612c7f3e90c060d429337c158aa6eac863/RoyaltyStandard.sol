// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0 <0.9.0;

import "./ERC165.sol";
import "./IERC2981.sol";

abstract contract RoyaltyStandard is ERC165, IERC2981 {
    mapping(uint256 => RoyaltyInfo) public royalties;

    /* information of NFT royalty */
    struct RoyaltyInfo {
        uint16 feeRate;
    }

    /* inverse basis point */
    uint16 public constant INVERSE_BASIS_POINT = 10000;

    uint16 public feeRateRef = 500;

    address public feeReceiver;

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        receiver = feeReceiver;
        uint16 feeRate = royalties[tokenId].feeRate;
        royaltyAmount = (salePrice * feeRate) / INVERSE_BASIS_POINT;
    }

    function _setTokenRoyalty(uint256 tokenId) internal {
        royalties[tokenId] = RoyaltyInfo(feeRateRef);
    }

    function _setFeeRate(uint16 feeRate_) internal {
        require(feeRate_ <= INVERSE_BASIS_POINT / 10, "too high, should less than 10%");
        feeRateRef = feeRate_;
    }

    function _setFeeReceiver(address feeReceiver_) internal {
        feeReceiver = feeReceiver_;
    }
}

