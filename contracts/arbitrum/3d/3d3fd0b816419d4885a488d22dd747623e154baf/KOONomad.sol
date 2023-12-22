// SPDX-License-Identifier: MIT-License
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";



contract KOONomad is Context, ReentrancyGuard, Pausable, Ownable {

    // Rank structure
    struct Rank {
      string name;
      uint index;
      uint256 totalToRaise;
      uint256 currentlyRaised;
      uint256 minAllocation;
      uint256 maxAllocation;
    }

    // Description of the multiple ranks available
    Rank NoRank = Rank(
      "NoRank (FCFS only)",
      0,
      0,
      0,
      10*10**6,
      1000*10**6
    );

    Rank Squire = Rank(
      "Squire",
      1,
      1000*10**6,
      0,
      10*10**6,
      100*10**6
    );

    Rank Knight = Rank(
        "Knight",
        2,
        3000*10**6,
        0,
        10*10**6,
        300*10**6
    );

    Rank Baron = Rank(
        "Baron",
        3,
        7000*10**6,
        0,
        10*10**6,
        700*10**6
    );

    Rank Prince = Rank(
        "Prince",
        4,
        7000*10**6,
        0,
        10*10**6,
        900*10**6
    );

    // Address where funds are collected. Here the Lys Gnosis on Arbitrum.
    address public wallet;

    // The veLys token
    ERC20 public veLys;

    // The name of the sale
    string public name;

    // The usdc token
    ERC20 public usdc;

    // Total raised is the amount of USDC to raise. Here 20k USDC.
    uint256 public totalToRaise = 20000*10**6;

    // Total amount of usdc raised currently
    uint256 public currentlyRaised = 0;

    // The max amount once in FCFS mode
    uint256 public maxAllocationFCFS = 1000*10**6;

    // The start of the auction
    uint public auctionStartTime;


    // Mapping to have the actual amount each user has.
    mapping (address => uint256) public nomadBalances;
    mapping (address => bool) public participatedInFCFS;
    mapping (uint => Rank) public ranks;

    /**
     * Event for token purchase logging
     * @param beneficiary who got the tokens
     * @param amountUSDC amount of usdc spent
     * @param amountNomad the amount of nomad token the beneficiary should receive
     */
    event TokensPurchased(address indexed beneficiary,uint256 indexed amountUSDC, uint256 indexed amountNomad);


    /**
     * @dev The constructor
     * @param _wallet Address where collected funds will be forwarded to
     * @param _name name of the sale
     * @param _usdcToken address of the usdc token
    * @param _veLysToken address of the veLys token
     */
    constructor (address _wallet, string memory _name, address _usdcToken, address _veLysToken) {
        require(_wallet != address(0), "Crowdsale: wallet is the zero address");
        wallet = _wallet;
        usdc = ERC20(_usdcToken);
        veLys = ERC20(_veLysToken);
        name = _name;
        auctionStartTime = block.timestamp;
        ranks[0] = NoRank;
        ranks[1] = Squire;
        ranks[2] = Knight;
        ranks[3] = Baron;
        ranks[4] = Prince;
    }

    /**
     * @dev token purchase function 
     * This function has a non-reentrancy guard, so it shouldn't be called by
     * another `nonReentrant` function.
     * @param _beneficiary Recipient of the token purchase
     * @param _amountUsdc Total amount of usdc in the smallest denomination of the token
     */
    function buyTokens(address _beneficiary, uint256 _amountUsdc) public nonReentrant whenNotPaused {
        Rank memory rank = getRank(_beneficiary);

        // checks:
        _preValidatePurchase(_beneficiary, _amountUsdc, rank);


        // effects:
        uint256 nomadAmount = _getNomadAmount(_amountUsdc);
        // each user can participate in the auction only once in the FCFS mode
        if (auctionStartTime + 24 hours < block.timestamp) {
            participatedInFCFS[_beneficiary] = true;
        }
        ranks[rank.index].currentlyRaised += _amountUsdc;
        currentlyRaised = currentlyRaised + _amountUsdc;
        nomadBalances[_beneficiary] += nomadAmount;

        // interactions:  transfer the amount of usdc to the wallet of Lys
        usdc.transferFrom(_beneficiary, wallet, _amountUsdc);
        // fire the event
        emit TokensPurchased(_beneficiary, _amountUsdc, nomadAmount);
    }

    /**
     * @dev performs checks before rest of the function 
     * @param _beneficiary Recipient of the token purchase
     * @param _amountUsdc amount of usdc in the smallest denomination of the token
     */
    function _preValidatePurchase(address _beneficiary, uint256 _amountUsdc, Rank memory rank) public view {
        require(_beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(_amountUsdc > 0, "Crowdsale: amount is zero");
        // FCFS mode
        if (auctionStartTime + 25 hours < block.timestamp) {
            require(participatedInFCFS[_beneficiary] == false, "FCFS mode : Crowdsale: user has already participated in the auction");
            require(_amountUsdc <= maxAllocationFCFS, "FCFS mode : Crowdsale: purchase amount is too high");
            require(_amountUsdc + currentlyRaised <= totalToRaise, "FCFS mode : Crowdsale: is already oversubscribed");
        } else {
            // normal mode
            require(nomadBalances[_beneficiary] == 0, "Crowdsale: beneficiary already participated");
            require(rank.totalToRaise > 0, "Crowdsale: cannot participate in FCFS mode right now");
            require(_amountUsdc <= rank.maxAllocation, "Crowdsale: purchase amount is too high");
            require(_amountUsdc >= rank.minAllocation, "Crowdsale: purchase amount is too low");
            require(_amountUsdc+ranks[rank.index].currentlyRaised <= rank.totalToRaise, "Crowdsale: is already oversubscribed in this rank");   
            // redundant check
            require(_amountUsdc + currentlyRaised <= totalToRaise, "Crowdsale: is already oversubscribed");
        }
    }

    /**
     * @dev returns the current rank of the user. The rank is calculated based on the amount of veLys tokens the beneficiary has
     * @param _beneficiary Recipient of the token purchase
    */
    function getRank(address _beneficiary) public view returns (Rank memory) {
        uint256 vlb = veLys.balanceOf(_beneficiary);
        if (vlb >= 5000*10**18 && vlb < 10000*10**18) {
            return Squire;
        } else if (vlb >= 10000*10**18 && vlb < 20000*10**18) {
            return Knight;
        } else if (vlb >= 20000*10**18 && vlb < 40000*10**18) {
            return Baron;
        } else if (vlb >= 40000*10**18) {
            return Prince;
        } else {
            return NoRank;
        }
    }

    /**
     * @dev returns the amount of nomad tokens the user should receive
     * @param _usdcAmount amount of usdc in the smallest denomination of the token
    */
    function _getNomadAmount(uint256 _usdcAmount) internal pure returns (uint256) {
       return (_usdcAmount*1e18)/(70000);
    }

    // View functions
    function getAmountLeftByRank(uint rank) public view returns (uint256) {
        return totalToRaise - ranks[rank].currentlyRaised;
    }

    // Security functions
    /**
    * @dev Function to save ERC20 tokens stuck in the contract
    * @param _contract erc20 contract address
    * @param _recipient receiver of funds
    * @param _amount amount of tokens to be transferred
    */
   function saveERC20(address _contract, address _recipient, uint256 _amount) public onlyOwner {
      ERC20 _token = ERC20(_contract);
      _token.transfer(_recipient, _amount);
    }

    /**
    * @dev Function to pause the contract
    */
    function pause() public onlyOwner {
      _pause();
    }  

    /**
    * @dev Function to unpause the contract
    */
    function unpause() public onlyOwner {
      _unpause();
    }   

    /**
     * @dev fallback function to prevent people from sending eth directly to the contract
     */
    receive() external payable {
        revert("The Crowdsale contract does not accepts ETH");
    }
}
