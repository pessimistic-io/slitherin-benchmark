// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface ISidPriceOracle {
    struct Price {
        uint256 base;
        uint256 premium;
        uint256 usedPoint;
    }

    function giftcard(
        uint256[] memory ids,
        uint256[] memory amounts
    ) external view returns (Price calldata);

    function domain(
        string memory name,
        uint256 expires,
        uint256 duration
    ) external view returns (Price calldata);

    function domainWithPoint(
        string memory name,
        uint256 expires,
        uint256 duration,
        address owner
    ) external view returns (Price calldata);
}

