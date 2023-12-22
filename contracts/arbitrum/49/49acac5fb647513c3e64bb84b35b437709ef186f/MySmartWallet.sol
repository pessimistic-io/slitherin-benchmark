// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./I1Inch.sol";

contract MySmartWallet is Ownable {
    using SafeERC20 for IERC20;

    address public trader;
    address public beneficiary;
    address public oneInchRouter;

    uint public unlockAt = 0;
    uint public unlockDaysWhenInheritanceRequested = 30;

    event TraderChanged(address indexed oldTrader, address indexed newTrader);
    event BeneficiaryChanged(
        address indexed oldBeneficiary,
        address indexed newBeneficiary
    );
    event TokensWithdrawn(address indexed token, uint256 amount);
    event EthWithdrawn(uint256 amount);
    event TokensInherited(address indexed token, uint256 amount);
    event EthInherited(uint256 amount);
    event InheritanceRequested();
    event InheritanceBlocked();
    event Swapped(
        address indexed fromToken,
        uint256 fromAmount,
        address indexed toToken,
        uint256 toAmount
    );

    modifier onlyTrader() {
        require(msg.sender == trader, "Caller is not the trader");
        _;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "Caller is not the beneficiary");
        _;
    }

    constructor(
        address _newOwner,
        address _trader,
        address _beneficiary,
        address _oneInchRouter
    ) {
        transferOwnership(_newOwner);
        trader = _trader;
        beneficiary = _beneficiary;
        oneInchRouter = _oneInchRouter;
    }

    receive() external payable {}

    function setTrader(address _trader) external onlyOwner {
        require(_trader != address(0), "Invalid trader address");
        emit TraderChanged(trader, _trader);
        trader = _trader;
    }

    function setBeneficiary(address _beneficiary) external onlyOwner {
        require(_beneficiary != address(0), "Invalid beneficiary address");
        emit BeneficiaryChanged(beneficiary, _beneficiary);
        beneficiary = _beneficiary;
    }

    function set1InchAddress(address _oneInchRouter) external onlyOwner {
        oneInchRouter = _oneInchRouter;
    }

    function withdrawTokens(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        require(
            _token != address(0) && _amount > 0,
            "Invalid token address or amount"
        );
        IERC20(_token).safeTransfer(owner(), _amount);
        emit TokensWithdrawn(_token, _amount);
    }

    function withdrawEth(uint256 _amount) external onlyOwner {
        require(
            _amount > 0 && address(this).balance >= _amount,
            "Invalid amount or insufficient balance"
        );
        payable(owner()).transfer(_amount);
        emit EthWithdrawn(_amount);
    }

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        uint256 exactIn,
        uint256 minOut,
        bytes calldata _data
    ) external onlyTrader returns (uint256 actualOut) {
        (, SwapDescription memory desc, , ) = abi.decode(
            _data[4:],
            (address, SwapDescription, bytes, bytes)
        );
        require(exactIn == desc.amount, "Unexpected in amount");
        require(desc.dstReceiver == address(this), "Invalid dstReceiver");

        bool isEthSwap = address(desc.srcToken) ==
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        if (!isEthSwap) {
            // Swapping from an ERC20 token
            IERC20(desc.srcToken).safeApprove(oneInchRouter, desc.amount);
        }

        (bool succ, bytes memory _res) = address(oneInchRouter).call{
            value: isEthSwap ? desc.amount : 0
        }(_data);

        if (succ) {
            (actualOut, ) = abi.decode(_res, (uint256, uint256));
            require(
                actualOut >= minOut,
                "Actual return amount less than minOut"
            );

            emit Swapped(
                address(desc.srcToken),
                desc.amount,
                address(desc.dstToken),
                actualOut
            );
        } else {
            revert();
        }
    }

    function setUnlockDaysWhenInheritanceRequested(
        uint _unlockDaysWhenInheritanceRequested
    ) external onlyOwner {
        require(
            _unlockDaysWhenInheritanceRequested > 0,
            "Unlock days should be greater than 0"
        );
        unlockDaysWhenInheritanceRequested = _unlockDaysWhenInheritanceRequested;
    }

    function blockInheritance() external onlyOwner {
        unlockAt = 0;
        emit InheritanceBlocked();
    }

    function requestInheritance() external onlyBeneficiary {
        unlockAt =
            block.timestamp +
            unlockDaysWhenInheritanceRequested *
            1 days;
        emit InheritanceRequested();
    }

    function inheritTokens(
        address _token,
        uint256 _amount
    ) external onlyBeneficiary {
        require(unlockAt != 0, "Request to unlock first");
        require(block.timestamp >= unlockAt, "You can't withdraw yet");
        require(
            _token != address(0) && _amount > 0,
            "Invalid token address or amount"
        );

        IERC20(_token).safeTransfer(beneficiary, _amount);
        emit TokensInherited(_token, _amount);
    }

    function inheritEth(uint256 _amount) external onlyBeneficiary {
        require(unlockAt != 0, "Request to unlock first");
        require(block.timestamp >= unlockAt, "You can't withdraw yet");
        require(
            _amount > 0 && address(this).balance >= _amount,
            "Invalid amount or insufficient balance"
        );
        payable(beneficiary).transfer(_amount);
        emit EthInherited(_amount);
    }
}

