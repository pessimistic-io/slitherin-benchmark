// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./IBulletOracle.sol";

contract BulletOracle is Ownable, IBulletOracle {
    uint64 public override baseLimit = 50;
    mapping(address => uint64) public override getBulletLimitBySender;
    mapping(uint64 => mapping(address => uint64)) public override getBulletLimitByCollection;

    function getMaxBullet(address _sender, uint64 _originChain, address _collection) public view returns (uint64) {
        return
            getBulletLimitBySender[_sender] == 0
                ? getBulletLimitByCollection[_originChain][_collection] == 0
                    ? baseLimit
                    : getBulletLimitByCollection[_originChain][_collection]
                : getBulletLimitBySender[_sender];
    }

    /// @dev dao
    function setBulletLimit(address _sender, uint64 _limit) public onlyOwner {
        getBulletLimitBySender[_sender] = _limit;
    }

    function setBulletLimit(uint64 _originChain, address _collection, uint64 _limit) public onlyOwner {
        getBulletLimitByCollection[_originChain][_collection] = _limit;
    }

    function setBaseBullet(uint64 _limit) public onlyOwner {
        baseLimit = _limit;
    }
}

