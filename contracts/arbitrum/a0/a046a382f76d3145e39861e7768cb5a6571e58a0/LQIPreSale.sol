//SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

contract LQIPreSale is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct PoolInfo {
        IERC20 token;
        uint256 decimals;
        uint256 rate;
    }

    IERC20 public LQI;
    PoolInfo[] public poolInfo;

    event Swap(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(IERC20 _LQI) {
        LQI = _LQI;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    modifier onlyOwnerOrGovernance() {
        require(
            owner() == _msgSender(),
            "Caller is not the owner, neither governance"
        );
        _;
    }

    function add(
        IERC20 _token,
        uint256 _decimals,
        uint256 _rate
    ) public onlyOwnerOrGovernance {
        poolInfo.push(
            PoolInfo({token: _token, decimals: _decimals, rate: _rate})
        );
    }

    function remove(uint256 _pid, uint256 _amount, address _to) public onlyOwnerOrGovernance {
        PoolInfo storage pool = poolInfo[_pid];
        TransferHelper.safeTransfer(address(pool.token), _to, _amount);
    }

    function updateRate(
        uint256 _pid,
        uint256 _rate
    ) public onlyOwnerOrGovernance {
        PoolInfo storage pool = poolInfo[_pid];
        pool.rate = _rate;
    }

    function swap(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 decimals = 10 ** (18 - uint256(pool.decimals));
        
        uint256 amount = _amount.mul(pool.rate).mul(decimals).div(1000000);

        TransferHelper.safeTransferFrom(address(pool.token), msg.sender, address(this), _amount);
        TransferHelper.safeTransfer(address(LQI), msg.sender, amount);

        emit Swap(msg.sender, _pid, _amount);
    }
}

