// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./IERC20Metadata.sol";

import "./IMasterChef.sol";
import "./IXToken.sol";
import "./INFTPoolRewardManager.sol";
import "./NFTPool.sol";

contract NFTPoolFactory {
    IMasterChef public immutable master; // Address of the master
    IERC20Metadata public immutable arxToken;
    IXToken public immutable xToken;

    // lp token => pool
    mapping(address => address) public getPool;
    address[] public pools;

    constructor(IMasterChef _master, IERC20Metadata _arxToken, IXToken _xToken) {
        master = _master;
        arxToken = _arxToken;
        xToken = _xToken;
    }

    event PoolCreated(address indexed lpToken, address pool);

    function poolsLength() external view returns (uint256) {
        return pools.length;
    }

    function createPool(address lpToken, INFTPoolRewardManager rewardManager) external returns (address pool) {
        require(getPool[lpToken] == address(0), "pool exists");
        require(address(rewardManager) != address(0), "manager not provided");

        bytes memory bytecode_ = type(NFTPool).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(lpToken));
        /* solhint-disable no-inline-assembly */
        assembly {
            pool := create2(0, add(bytecode_, 32), mload(bytecode_), salt)
        }
        require(pool != address(0), "failed");

        NFTPool(pool).initialize(master, arxToken, xToken, IERC20Metadata(lpToken), rewardManager);
        getPool[lpToken] = pool;
        pools.push(pool);

        emit PoolCreated(lpToken, pool);
    }
}

