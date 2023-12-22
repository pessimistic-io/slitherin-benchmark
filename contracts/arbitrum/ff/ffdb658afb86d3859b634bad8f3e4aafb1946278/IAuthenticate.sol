// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

interface IAuthenticate {
    // check is autherized
    function isAuthorized(address shareId) external view returns (bool);

    function authorizeTwitter(address shareId, uint256 twitterId) external;

    function getShareIdByTwitterId(
        uint256 twitterId
    ) external view returns (address);

    function getShareTwitterId(address shareId) external view returns (uint256);
}

