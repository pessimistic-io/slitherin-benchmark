pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract InterestTokenDeer {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public owner;
    address public deerLokingAddress;
    IERC20 public token;
    uint256 public lastAddressChangeTimestamp;

    constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only DeerLoking can perform this action."
        );
        _;
    }

    modifier onlyDeerLoking() {
        require(
            msg.sender == deerLokingAddress,
            "Only DeerLoking can perform this action."
        );
        _;
    }

    // Allow owner to set DeerLoking address
    function setDeerLokingAddress(
        address _deerLokingAddress
    ) external onlyOwner {
        deerLokingAddress = _deerLokingAddress;
    }

    // Allow the owner to deposit ERC20 tokens to pay interest
    function deposit(uint256 _amount) external {
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    // Withdraw ERC20 tokens to pay interest to users
    function withdrawInterest(
        address _recipient,
        uint256 _amount
    ) external onlyDeerLoking {
        token.safeTransfer(_recipient, _amount);
    }

    // Check the current balance of tokens in the contract
    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}

