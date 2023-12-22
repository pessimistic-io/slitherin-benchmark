// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {IFeeReceiver} from "./IFeeReceiver.sol";

contract JonesFeeReceiver is IFeeReceiver, Ownable {
    // Registry of allowed depositors
    mapping(address => bool) public depositors;

    /**
     * @param _governor The address of the owner of this contract
     */
    constructor(address _governor) {
        _transferOwnership(_governor);
    }

    /**
     * @notice To enforce only allowed depositors to deposit funds
     */
    modifier onlyDepositors() {
        if (!depositors[msg.sender]) {
            revert NotAuthorized();
        }
        _;
    }

    /**
     * @notice Used by depositors to deposit fees
     * @param _token the address of the asset to be deposited
     * @param _amount the amount of `_token` to deposit
     */
    function deposit(address _token, uint256 _amount) external onlyDepositors {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _token, _amount);
    }

    /**
     * @notice Used to register new depositors
     * @param _depositor the address of the new depositor
     */
    function addDepositor(address _depositor) external onlyOwner {
        _isValidAddress(_depositor);

        depositors[_depositor] = true;

        emit DepositorAdded(msg.sender, _depositor);
    }

    /**
     * @notice Used to remove depositors
     * @param _depositor the address of the depositor to remove
     */
    function removeDepositor(address _depositor) external onlyOwner {
        depositors[_depositor] = false;

        emit DepositorRemoved(msg.sender, _depositor);
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function withdraw(
        address _to,
        address[] memory _assets,
        bool _withdrawNative
    ) external onlyOwner {
        _isValidAddress(_to);

        for (uint256 i; i < _assets.length; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            // No need to transfer
            if (assetBalance == 0) {
                continue;
            }

            // Transfer the ERC20 tokens
            asset.transfer(_to, assetBalance);
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            payable(_to).transfer(nativeBalance);
        }

        emit Withdrawal(msg.sender, _to, _assets, _withdrawNative);
    }

    function _isValidAddress(address _address) internal {
        if (_address == address(0)) {
            revert InvalidAddress();
        }
    }

    /**
     * @notice Emitted when a depositor deposits fees
     * @param depositor the contract that deposited
     * @param token the address of the asset that was deposited
     * @param amount the amount of `token` that was deposited
     */
    event Deposit(
        address indexed depositor,
        address indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted when a new depositor is registered
     * @param owner the current owner of this contract
     * @param depositor the address of the new depositor
     */
    event DepositorAdded(address indexed owner, address indexed depositor);

    /**
     * @notice Emitted when a new depositor is registered
     * @param owner the current owner of this contract
     * @param depositor the address of the new depositor
     */
    event DepositorRemoved(address indexed owner, address indexed depositor);

    event Withdrawal(
        address owner,
        address receiver,
        address[] assets,
        bool includeNative
    );

    error NotAuthorized();
    error InvalidAddress();
}

