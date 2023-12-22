// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./IERC20.sol";

import "./IERC3156FlashLender.sol";

abstract contract FlashLoanPool is IERC3156FlashLender, Initializable {
    address public token;

    // 10000 = 100%
    uint256 public constant FEE = 10;

    event FlashLoanBorrowed(
        address indexed lender,
        address indexed borrower,
        address indexed stablecoin,
        uint256 amount,
        uint256 fee
    );

    function __FlashLoan__Init(address _usdc) internal onlyInitializing {
        token = _usdc;
    }

    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external override returns (bool) {
        require(_amount > 0, "Zero amount");

        uint256 fee = flashFee(_token, _amount);

        uint256 previousBalance = IERC20(_token).balanceOf(address(this));

        IERC20(_token).transfer(address(_receiver), _amount);
        require(
            _receiver.onFlashLoan(msg.sender, _token, _amount, fee, _data) ==
                keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "IERC3156: Callback failed"
        );
        IERC20(_token).transferFrom(
            address(_receiver),
            address(this),
            _amount + fee
        );

        uint256 finalBalance = IERC20(_token).balanceOf(address(this));
        require(finalBalance >= previousBalance + fee, "Not enough pay back");

        emit FlashLoanBorrowed(
            address(this),
            address(_receiver),
            _token,
            _amount,
            fee
        );

        return true;
    }

    function flashFee(address _token, uint256 _amount)
        public
        view
        override
        returns (uint256)
    {
        require(_token == token, "Only usdc");
        return (_amount * FEE) / 10000;
    }

    function maxFlashLoan(address _token) external view returns (uint256) {
        require(_token == token, "only usdc");
        return IERC20(token).balanceOf(address(this));
    }
}

