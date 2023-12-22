// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;


/**
 * @dev Modifier 'onlyOwner' becomes available, where owner is the contract deployer
 */ 
import "./Ownable.sol";

/**
 * @dev ERC20 token interface
 */
import "./IERC20.sol";

/**
 * @dev Allows use of SafeERC20 transfer functions
 */
import "./SafeERC20.sol";

/**
 * @dev Makes mofifier nonReentrant available for use
 */
import "./ReentrancyGuard.sol";
/**
 * @dev Exposes 'whenNotPaused' modifier and '_pause', '_unpause' methods
 */
import "./Pausable.sol";


contract Claim is Ownable, Pausable, ReentrancyGuard {


    using SafeERC20 for IERC20;

    IERC20 public xcal;


    // --- CONSTRUCTOR --- //

    constructor(address _xcal) {
        xcal = IERC20(_xcal);

        _pause();
    }


    // --- EVENTS --- //
    event Claimed(address indexed claimant, address indexed recipient, uint amountClaimed);


    // --- MAPPINGS --- /

    mapping(address => uint) addressToAmount;


    // --- USER --- //

    function claim(address _recipient) external nonReentrant whenNotPaused {

        require(
            addressToAmount[msg.sender] > 0,
            "Nothing to claim"
        );

        uint amount = addressToAmount[msg.sender];
        addressToAmount[msg.sender] = 0;

        IERC20(xcal).safeTransfer(_recipient, amount);

        emit Claimed(msg.sender, _recipient, amount);
    }


    // --- VIEW --- //

    function claimableAmount(address _user) external view returns(uint) {

        return addressToAmount[_user];
    }


    // --- OWNER --- /

    /**
     * @dev Set XCAL balances
     */
    function setBalances(
        address[] memory _addresses,
        uint[] memory _balances
        ) external onlyOwner {

        require(
            _addresses.length == _balances.length,
            "Array sizes differ"
        );
        
        for (uint i; i<_addresses.length; i++) {
            addressToAmount[_addresses[i]] = _balances[i];
        }
    }

    /**
     * @dev Withdraw ERC20 tokens from contract
     * @param _token - address of token to withdraw
     * @param _to - recipient of token transfer
     * @param _amount - amount of tokens to trasnfer
     */
    function withdrawERC20(
        address _token,
        address _to,
        uint _amount
        ) external onlyOwner {

        require(
            _amount <= IERC20(_token).balanceOf(address(this)),
            "Withdrawal amount greater than contract balance"
        );

        IERC20(_token).safeTransfer(_to, _amount);
    }

    /**
     * @dev Pause claiming
     */
     function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Resume claiming
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
}

