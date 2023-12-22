// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// openzeppelin
import "./SafeMath.sol";

// diy
import "./IBondingCurve.sol";
import "./ABDKMath.sol";

contract SqrtMixedBondingSwap is IBondingCurve {
    using ABDKMath for uint256;
    string public constant BondingCurveType = "squareroot";

    function getParameter(bytes memory data) private pure returns (uint256 a) {
        a = abi.decode(data, (uint256));
    }

    // x => erc20, y => native
    // p(x) = a * sqrt(x)
    function calculateMintAmountFromBondingCurve(
        uint256 nativeTokenAmount,
        uint256 daoTokenCurrentSupply,
        bytes memory parameters
    ) public pure override returns (uint256 daoTokenAmount, uint256) {
        uint256 a = getParameter(parameters);
        uint256 sdb = daoTokenCurrentSupply.sqrt();
        uint256 cna = ((3e18 * nativeTokenAmount) / (2 * a) + sdb * sdb * sdb).cuberoot();
        daoTokenAmount = cna * cna - daoTokenCurrentSupply;
        return (daoTokenAmount, nativeTokenAmount);
    }

    function calculateBurnAmountFromBondingCurve(
        uint256 daoTokenAmount,
        uint256 daoTokenCurrentSupply,
        bytes memory parameters
    ) public pure override returns (uint256, uint256 nativeTokenAmount) {
        uint256 a = getParameter(parameters);
        uint256 sdb = daoTokenCurrentSupply.sqrt();
        uint256 sda = (daoTokenCurrentSupply - daoTokenAmount).sqrt();
        nativeTokenAmount = (2 * a * (sdb * sdb * sdb - sda * sda * sda)) / 3e18;
        return (daoTokenAmount, nativeTokenAmount);
    }

    function price(uint256 daoTokenCurrentSupply, bytes memory parameters) public pure override returns (uint256) {
        uint256 a = getParameter(parameters);
        return a * daoTokenCurrentSupply.sqrt();
    }
}

