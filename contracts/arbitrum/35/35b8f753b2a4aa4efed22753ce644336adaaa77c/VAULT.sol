// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeERC20.sol";

import "./ISmartYield.v1.sol";
import "./IHop.sol";
import "./IBridge.sol";
import "./IL1Bridge.sol";

contract Vault is Ownable {
    using SafeERC20 for IERC20;

    address public constant DAO = address(0xB8a49c3137f27b04ee9E68727147b3131764B8A0);
    // Optimism chain id 10
    uint256 public constant TO_CHAIN_ID = 10;
    // L2_AMM_WRAPPER for DAI on polygon, from https://github.com/hop-protocol/hop/blob/develop/packages/core/src/addresses/mainnet.ts
    address public constant HOP_ADDRESS = address(0x28529fec439cfF6d7D1D5917e956dEE62Cd3BE5c);
    // L1_bridge for DAI, from
    // address public constant HOP_ADDRESS = address(0x3d4Cc8A61c7528Fd86C55cfe061a78dCBA48EDd1);

    IERC20 private _underlying;
    ISmartYield private _smartYield;

    constructor(address smartYield_) {
        _smartYield = ISmartYield(smartYield_);
        _underlying = IERC20(_smartYield.underlying());
    }

    event MoveBackToDAO(address indexed caller, address indexed daoAddress, uint256 amount);
    event Spent(address indexed caller, address indexed spender, uint256 amount);
    event Received(address indexed caller, uint256 amount);

    // TODO: also need to add desitination chain tx fee
    function _computeBonderFee(uint256 amount) internal view returns (uint256) {
        IBridge bridge = IBridge(IHop(HOP_ADDRESS).bridge());
        uint256 minBonderFeeAbsolute = bridge.minBonderFeeAbsolute();
        uint256 minBonderBps = bridge.minBonderBps();
        uint256 minBonderFeeRelative = (minBonderBps * amount) / 10000;
        uint256 bonderFee;
        if (minBonderFeeAbsolute < minBonderFeeRelative) {
            bonderFee = minBonderFeeRelative;
        } else {
            bonderFee = minBonderFeeAbsolute;
        }
        return bonderFee;
    }

    function _moveOutFromL2(
        uint256 _amount,
        uint256 _bonderFee,
        uint256 _amountOutMin,
        uint256 _deadline
    ) internal {
        require(msg.value == 0, "msg.value must be zero");
        _underlying.safeIncreaseAllowance(HOP_ADDRESS, _amount);
        IHop(HOP_ADDRESS).swapAndSend(
            TO_CHAIN_ID,
            DAO,
            _amount,
            _bonderFee,
            _amountOutMin,
            _deadline,
            _amountOutMin,
            _deadline
        );
    }

    function _calculateAmountToMove(uint256 amount) internal view returns (uint256) {
        uint256 balance = _underlying.balanceOf(address(this));
        uint256 amountToMove;
        if (amount > balance) {
            amountToMove = balance;
        } else {
            amountToMove = amount;
        }
        return amountToMove;
    }

    function moveBackToDAOL1toL2(
        uint256 amount,
        uint256 _amountOutMin,
        uint256 _deadline
    ) external onlyOwner {
        uint256 amountToMove = _calculateAmountToMove(amount);
        _underlying.safeIncreaseAllowance(HOP_ADDRESS, amountToMove);
        IL1Bridge(HOP_ADDRESS).sendToL2(TO_CHAIN_ID, DAO, amountToMove, _amountOutMin, _deadline, address(0), 0);
        emit MoveBackToDAO(msg.sender, DAO, amountToMove);
    }

    function moveBackToDAOL1toL1(uint256 amount) external onlyOwner {
        uint256 amountToMove = _calculateAmountToMove(amount);
        _underlying.safeTransfer(DAO, amountToMove);
        emit MoveBackToDAO(msg.sender, DAO, amountToMove);
    }

    function moveBackToDAOFromL2(
        uint256 amount,
        uint256 bonderFee,
        uint256 _amountOutMin,
        uint256 _deadline
    ) external onlyOwner {
        uint256 amountToMove = _calculateAmountToMove(amount);
        uint256 _bonderFee;
        if (bonderFee > 0) {
            _bonderFee = bonderFee;
        } else {
            revert("bonderFee must be greater than zero");
            // TODO: this requires extra work to calculate actual bonder fee in SC
            // _bonderFee = _computeBonderFee(amountToMove);
        }
        _moveOutFromL2(amountToMove, _bonderFee, _amountOutMin, _deadline);
        emit MoveBackToDAO(msg.sender, DAO, amountToMove);
    }

    function addLiquidity(uint256 amount) external onlyOwner {
        address spender = _smartYield.bondProvider();
        _underlying.safeApprove(spender, amount);
        _smartYield.addLiquidity(amount);
        emit Spent(msg.sender, spender, amount);
    }

    function removeLiquidity(uint256 amount) external onlyOwner {
        _smartYield.removeLiquidity(amount);
        emit Received(msg.sender, amount);
    }

    function provideRealizedYield(address bond, uint256 amount) external onlyOwner {
        address spender = _smartYield.bondProvider();
        _underlying.safeApprove(spender, amount);
        _smartYield.provideRealizedYield(bond, amount);
        emit Spent(msg.sender, spender, amount);
    }
}

