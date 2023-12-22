pragma solidity 0.8.17;

import "./LibDiamond.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./SafeERC20.sol";
import "./IBridge.sol";
import "./ReentrancyGuard.sol";

interface IMesonMinimal {
    function tokenForIndex(uint8 tokenIndex) external returns (address token);

    function postSwapFromContract(uint256 encodedSwap, uint200 postingValue, address fromContract) external;
}

contract MesonTestFacet is ReentrancyGuard, IBridge {
    using SafeERC20 for IERC20;

    IMesonMinimal private immutable MESON;

    constructor(address _meson) {
        MESON = IMesonMinimal(_meson);
    }

    function amountFrom(uint256 encodedSwap) external view returns (uint256) {
        return (encodedSwap >> 208) & 0xFFFFFFFFFF;
    }

    // function tokenAddress(uint256 encodedSwap) external view returns (address) {
    //     address token = MESON.tokenForIndex(_inTokenIndexFrom(encodedSwap));
    //     return token;
    // }

    function _inTokenIndexFrom(uint256 encodedSwap) internal pure returns (uint8) {
        return uint8(encodedSwap);
    }

    function updateEncodedSwap(uint256 encodedSwap, uint256 amount) external view returns (uint256) {
        uint256 updatedEncodedSwap = (encodedSwap & ~(uint256(0xFFFFFFFFFF) << 208)) | ((amount & 0xFFFFFFFFFF) << 208);

        return updatedEncodedSwap;
    }
}

