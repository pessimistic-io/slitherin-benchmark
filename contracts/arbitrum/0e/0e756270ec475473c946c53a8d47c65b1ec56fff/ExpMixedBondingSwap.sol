// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// openzeppelin
import "./SafeMath.sol";

// abdk-consulting
// "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol";
import "./ABDKMath64x64.sol";

// diy
import "./IBondingCurve.sol";

contract ExpMixedBondingSwap is IBondingCurve {
    using ABDKMath64x64 for int128;
    string public constant BondingCurveType = "exponential";

    function getParameter(bytes memory data) private pure returns (uint256 a, uint256 b) {
        (a, b) = abi.decode(data, (uint256, uint256));
    }

    // x => daoTokenAmount, y => nativeTokenAmount
    // y = (a) e**(x/b)
    // daoTokenAmount = b * ln(e ^ (daoTokenCurrentSupply / b) + nativeTokenAmount / a) - daoTokenCurrentSupply
    function calculateMintAmountFromBondingCurve(
        uint256 nativeTokenAmount,
        uint256 daoTokenCurrentSupply,
        bytes memory parameters
    ) public pure override returns (uint256 daoTokenAmount, uint256) {
        (uint256 a, uint256 b) = getParameter(parameters);
        require(daoTokenCurrentSupply < uint256(1 << 192));
        require(nativeTokenAmount < uint256(1 << 192));
        uint256 e_index = (daoTokenCurrentSupply << 64) / b;
        uint256 e_mod = (nativeTokenAmount << 64) / a;
        require(e_index <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        require(e_mod <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        int128 fabdk_e_index = int128(uint128(e_index));
        int128 fabdk_e_mod = int128(uint128(e_mod));
        int128 fabdk_x = (fabdk_e_index.exp() + fabdk_e_mod).ln();
        require(fabdk_x >= 0);
        daoTokenAmount = (((uint256(uint128(fabdk_x))) * b) >> 64) - daoTokenCurrentSupply;
        return (daoTokenAmount, nativeTokenAmount);
    }

    // x => daoTokenAmount, y => nativeTokenAmount
    // y = (a) e**(x/b)
    // nativeTokenAmount = a * (e ^ (daoTokenCurrentSupply / b) - e ^ ((daoTokenCurrentSupply - daoTokenAmount) / b))
    function calculateBurnAmountFromBondingCurve(
        uint256 daoTokenAmount,
        uint256 daoTokenCurrentSupply,
        bytes memory parameters
    ) public pure override returns (uint256, uint256 nativeTokenAmount) {
        (uint256 a, uint256 b) = getParameter(parameters);
        require(daoTokenCurrentSupply < uint256(1 << 192));
        require(daoTokenAmount < uint256(1 << 192));
        uint256 e_index_1 = (daoTokenCurrentSupply << 64) / b;
        uint256 e_index_0 = ((daoTokenCurrentSupply - daoTokenAmount) << 64) / b;
        require(e_index_1 <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        require(e_index_0 <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        int128 fabdk_e_index_1 = int128(uint128(e_index_1));
        int128 fabdk_e_index_0 = int128(uint128(e_index_0));
        int128 fabdk_y = fabdk_e_index_1.exp() - fabdk_e_index_0.exp();
        require(fabdk_y >= 0);
        nativeTokenAmount = ((uint256(uint128(fabdk_y))) * a) >> 64;
        return (daoTokenAmount, nativeTokenAmount);
    }

    // price = a / b * e ^ (daoTokenCurrentSupply / b)
    function price(uint256 daoTokenCurrentSupply, bytes memory parameters) public pure override returns (uint256) {
        (uint256 a, uint256 b) = getParameter(parameters);
        uint256 e_index = (daoTokenCurrentSupply << 64) / b;
        require(e_index <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        int128 fabdk_e_index = int128(uint128(e_index));
        int128 fabdk_y = fabdk_e_index.exp();
        require(fabdk_y >= 0);
        uint256 p = (((uint256(uint128(fabdk_y))) * a * 1e18) / b) >> 64;
        return p;
    }
}

