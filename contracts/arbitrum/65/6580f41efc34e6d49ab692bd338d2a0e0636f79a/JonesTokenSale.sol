// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/
pragma solidity ^0.8.2;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeMath} from "./SafeMath.sol";

/// @author Jones DAO
/// @title Jones token sale contract
contract JonesTokenSale {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Jones Token
    IERC20 public jones;

    // Withdrawer
    address public owner;

    // Keeps track of ETH deposited
    uint256 public weiDeposited;

    // Time when the token sale starts
    uint256 public saleStart;

    // Time when the token sale closes
    uint256 public saleClose;

    // Max cap on wei raised
    uint256 public maxDeposits;

    // Jones Tokens allocated to this contract
    uint256 public jonesTokensAllocated;

    // Total sale participants
    uint256 public totalSaleParticipants;

    // Amount each user deposited
    mapping(address => uint256) public deposits;

    /// Emits on ETH deposit
    /// @param purchaser contract caller purchasing the tokens on behalf of beneficiary
    /// @param beneficiary will be able to claim tokens after saleClose
    /// @param value amount of ETH deposited
    /// @param time block timestamp
    event TokenDeposit(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 time
    );

    /// Emits on token claim
    /// @param claimer contract caller claiming on behalf of beneficiary
    /// @param beneficiary receives the tokens they claimed
    /// @param amount token amount beneficiary claimed
    event TokenClaim(
        address indexed claimer,
        address indexed beneficiary,
        uint256 amount
    );

    /// Emits on eth withdraw
    /// @param amount amount of Eth that was withdrawn
    event WithdrawEth(uint256 amount);

    /// @param _jones JONES
    /// @param _owner withdrawer
    /// @param _saleStart time when the token sale starts
    /// @param _saleClose time when the token sale closes
    /// @param _maxDeposits max cap on wei raised
    /// @param _jonesTokensAllocated JONES tokens allocated to this contract
    constructor(
        address _jones,
        address _owner,
        uint256 _saleStart,
        uint256 _saleClose,
        uint256 _maxDeposits,
        uint256 _jonesTokensAllocated
    ) {
        require(_owner != address(0), "invalid owner address");
        require(_jones != address(0), "invalid token address");
        require(_saleStart >= block.timestamp, "invalid saleStart");
        require(_saleClose > _saleStart, "invalid saleClose");
        require(_maxDeposits > 0, "invalid maxDeposits");
        require(_jonesTokensAllocated > 0, "invalid jonesTokensAllocated");

        jones = IERC20(_jones);
        owner = _owner;
        saleStart = _saleStart;
        saleClose = _saleClose;
        maxDeposits = _maxDeposits;
        jonesTokensAllocated = _jonesTokensAllocated;
    }

    /// Deposit fallback
    /// @dev must be equivalent to deposit(address beneficiary)
    receive() external payable isEligibleSender {
        address beneficiary = msg.sender;

        require(beneficiary != address(0), "invalid address");
        require(msg.value > 0, "invalid amount");
        require(
            msg.value <= 40 ether && msg.value >= 0.01 ether,
            "invalid amount"
        );
        require(
            (weiDeposited + msg.value) <= maxDeposits,
            "maximum deposits reached"
        );
        require(saleStart <= block.timestamp, "sale hasn't started yet");
        require(block.timestamp <= saleClose, "sale has closed");

        // Update total sale participants
        if (deposits[beneficiary] == 0) {
            totalSaleParticipants = totalSaleParticipants.add(1);
        }

        deposits[beneficiary] = deposits[beneficiary].add(msg.value);
        weiDeposited = weiDeposited.add(msg.value);
        emit TokenDeposit(msg.sender, beneficiary, msg.value, block.timestamp);
    }

    /// Deposit
    /// @param beneficiary will be able to claim tokens after saleClose
    /// @dev must be equivalent to receive()
    function deposit(address beneficiary) public payable isEligibleSender {
        require(beneficiary != address(0), "invalid address");
        require(msg.value > 0, "invalid amount");
        require(
            msg.value <= 40 ether && msg.value >= 0.01 ether,
            "invalid amount"
        );
        require(
            (weiDeposited + msg.value) <= maxDeposits,
            "maximum deposits reached"
        );
        require(saleStart <= block.timestamp, "sale hasn't started yet");
        require(block.timestamp <= saleClose, "sale has closed");

        // Update total sale participants
        if (deposits[beneficiary] == 0) {
            totalSaleParticipants = totalSaleParticipants.add(1);
        }

        deposits[beneficiary] = deposits[beneficiary].add(msg.value);
        weiDeposited = weiDeposited.add(msg.value);
        emit TokenDeposit(msg.sender, beneficiary, msg.value, block.timestamp);
    }

    /// Claim
    /// @param beneficiary receives the tokens they claimed
    /// @dev claim calculation must be equivalent to claimAmount(address beneficiary)
    function claim(address beneficiary) external returns (uint256) {
        require(deposits[beneficiary] > 0, "no deposit");
        require(block.timestamp > saleClose, "sale hasn't closed yet");

        // total Jones allocated * user share in the ETH deposited
        uint256 beneficiaryClaim = jonesTokensAllocated
            .mul(deposits[beneficiary])
            .div(weiDeposited);
        deposits[beneficiary] = 0;

        jones.safeTransfer(beneficiary, beneficiaryClaim);

        emit TokenClaim(msg.sender, beneficiary, beneficiaryClaim);

        return beneficiaryClaim;
    }

    /// @dev Withdraws eth deposited into the contract. Only owner can call this.
    function withdraw() external {
        require(owner == msg.sender, "caller is not the owner");

        uint256 ethBalance = payable(address(this)).balance;

        payable(msg.sender).transfer(ethBalance);

        emit WithdrawEth(ethBalance);
    }

    /// View beneficiary's claimable token amount
    /// @param beneficiary address to view claimable token amount
    /// @dev claim calculation must be equivalent to the one in claim(address beneficiary)
    function claimAmount(address beneficiary) external view returns (uint256) {
        if (weiDeposited == 0) {
            return 0;
        }

        // total Jones allocated * user share in the ETH deposited
        return
            jonesTokensAllocated.mul(deposits[beneficiary]).div(weiDeposited);
    }

    // Modifier is eligible sender modifier
    modifier isEligibleSender() {
        require(
            msg.sender == tx.origin,
            "Contracts are not allowed to snipe the sale"
        );
        _;
    }
}

