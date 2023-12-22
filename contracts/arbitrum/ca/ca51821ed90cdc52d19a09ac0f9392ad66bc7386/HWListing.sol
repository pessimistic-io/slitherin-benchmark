// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./IHWRegistry.sol";
import "./IUniswapV2Router01.sol";
import "./IPool.sol";

/// @title HonestWork Job Listing Contract
/// @author @takez0_o, @ReddKidd
/// @notice Accepts listing payments and distributes earnings
contract HWListing is Ownable {
    struct Payment {
        address token;
        uint256 amount;
        uint256 listingDate;
    }

    IHWRegistry public registry;
    mapping(address => Payment[]) payments;

    constructor(address _registry) {
        registry = IHWRegistry(_registry);
    }

    modifier checkWhitelist(address _token) {
        require(registry.isWhitelisted(_token), "Not whitelisted");
        _;
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function updateRegistry(address _registry) external onlyOwner {
        registry = IHWRegistry(_registry);
    }

    function withdrawToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function withdrawToken(address _token) external onlyOwner {
        IERC20(_token).transfer(
            msg.sender,
            IERC20(_token).balanceOf(address(this))
        );
    }

    function withdrawToken() external onlyOwner {
        uint256 counter = registry.counter();
        for (uint256 i = 0; i < counter; i++) {
            if (registry.getWhitelist()[i].token != address(0)) {
                IERC20(registry.getWhitelist()[i].token).transfer(
                    msg.sender,
                    IERC20(registry.getWhitelist()[i].token).balanceOf(
                        address(this)
                    )
                );
            }
        }
    }

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function payForListing(address _token, uint256 _amount)
        external
        checkWhitelist(_token)
    {
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        payments[msg.sender].push(Payment(_token, _amount, block.timestamp));
        emit PaymentAdded(_token, _amount);
    }

    //----------------//
    //  view methods  //
    //----------------//

    function getPayments(address _user)
        external
        view
        returns (Payment[] memory)
    {
        return payments[_user];
    }

    function getLatestPayment(address _user)
        external
        view
        returns (Payment memory)
    {
        return payments[_user][payments[_user].length - 1];
    }

    event PaymentAdded(address indexed _token, uint256 _amount);
}

