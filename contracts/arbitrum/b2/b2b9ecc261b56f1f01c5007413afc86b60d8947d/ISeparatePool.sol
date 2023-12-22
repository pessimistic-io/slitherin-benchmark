// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";

interface ISeparatePool is IERC721Receiver {
    event OwnerChanged(address oldOwner, address newOwner);
    event SoldNFT(uint256 indexed id, address indexed seller);
    event BoughtNFT(uint256 indexed id, address indexed buyer);
    event LockedNFT(uint256 indexed id, address indexed locker, uint256 timeOfLock, uint256 expiryTime);
    event RedeemedNFT(uint256 indexed id, address indexed redeemer);
    event ReleasedNFT(uint256 indexed id);

    function factory() external view returns (address);

    function owner() external view returns (address);

    function changeOwner(address _newOwner) external;

    function setFur(address _newFur) external;

    function setIncomeMaker(address _newIncomeMaker) external;

    function sell(uint256 _id) external;

    function buy(uint256 _id) external;

    function lock(uint256 _id) external;

    function redeem(uint256 _id) external;

    function release(uint256 _id) external;
}

