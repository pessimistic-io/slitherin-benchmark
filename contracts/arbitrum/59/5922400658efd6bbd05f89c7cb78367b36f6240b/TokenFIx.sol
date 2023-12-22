pragma solidity 0.8.10;
import "./IERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract TokenFix is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public oldToken;
    IERC20 public newToken;
    address public admin;

    event tokenClaimed (address claimer, uint256 claimAmount);
    event adminUpdated (address oldAdmin, address newAdmin);

    constructor(IERC20 _oldToken, IERC20 _newToken, address _admin) {
        oldToken = _oldToken;
        newToken = _newToken;
        admin = _admin;
    }


    function swap (uint256 swapAmount) nonReentrant public {
        swapInternal(swapAmount);
    }

    //@notice this function is to swap old tokens for new tokens at a 1:1 rate (?) 
    function swapInternal (uint256 swapAmount) internal {
        uint256 userBalance = IERC20(oldToken).balanceOf(msg.sender);

        if (swapAmount > userBalance) {
            revert('Swap amount exceeds balance');
        }

        userBalance = userBalance - swapAmount;

        oldToken.safeTransferFrom(msg.sender, address(this), swapAmount);

        newToken.safeTransferFrom(address(this), msg.sender, swapAmount);

        emit tokenClaimed (msg.sender, swapAmount);

    }

    //**ADMIN FUNCTIONS**

    function _setAdmin (address _newAdmin) public {
        require(msg.sender == admin, "Only the admin may update the admin");
        address oldAdmin = admin;
        admin = _newAdmin;
        emit adminUpdated(oldAdmin, admin);
    }

    function _adminTransferAll () public {
        require(msg.sender == admin, "Only the admin may transfer tokens out");
        uint256 amount = newToken.balanceOf(address(this));
        newToken.safeTransferFrom(address(this), msg.sender, amount);
    }

    function _adminTransfer (uint256 amount) public {
        require(msg.sender == admin, "Only the admin may transfer tokens out");
        newToken.safeTransferFrom(address(this), msg.sender, amount);
    }
    
}
