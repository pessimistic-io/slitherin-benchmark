// SPDX-License-Identifier: MIT-License
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Ownable.sol";


contract KOOGogocoin is Context, ReentrancyGuard, Pausable, Ownable {

    using SafeERC20 for IERC20;

    // The name of the sale
    string public name;

    // The usdc token
    ERC20 public usdc;

    // The lys token
    ERC20 public lys;

    // Address where funds are collected. Here the Lys Gnosis on Arbitrum.
    address public wallet;

    // Burn address for Lys Tokens
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    // Total raised is the amount of USDC to raise. Here 50k USDC.
    uint256 public totalRaised = 50000*10**6;

    // Smallest allocation
    uint256 public minAllocation = 50*10**6;

    // Biggest allocation
    uint256 public maxAllocation = 500*10**6;

    // Users with reduction (payed in LYS). Maps the address to the countribution.
    mapping (address => uint256) private reduced;

    // Users without the reduction. Maps the address to the countribution.
    mapping (address => uint256) private notReduced;

    // Mapping to have the actual amount each user has.
    mapping (address => uint256) private gogoBalances;

    // Amount of usdc raised
    uint256 private usdcRaised = 0;

    // Amount of lys burned
    uint256 private lysBurned = 0;

    /**
     * Event for token purchase logging
     * @param beneficiary who got the tokens
     * @param amountUSDC amount of usdc spent
     * @param amountGogo the beneficiary should receive
     * @param reduced was lys burned
     */
    event TokensPurchased(address indexed beneficiary,uint256 indexed amountUSDC, uint256 indexed amountGogo, bool reduced);

    /**
     * @dev The constructor
     * @param _wallet Address where collected funds will be forwarded to
     */
    constructor (address _wallet, string memory _name, address _usdcToken, address _lysToken) {
        require(_wallet != address(0), "Crowdsale: wallet is the zero address");
        wallet = _wallet;
        usdc = ERC20(_usdcToken);
        lys = ERC20(_lysToken);
        name = _name;
    }

    /**
     * @dev token purchase function 
     * This function has a non-reentrancy guard, so it shouldn't be called by
     * another `nonReentrant` function.
     * @param _beneficiary Recipient of the token purchase
     * @param _amountUsdc Total amount of usdc in the smallest denomination of the token
     */
    function buyTokens(address _beneficiary, uint256 _amountUsdc, bool _reduction) public nonReentrant whenNotPaused {

        // first checks 
        _preValidatePurchase(_beneficiary, _amountUsdc);
        
        // then transfer the amount of usdc to the wallet of Lys
        usdc.transferFrom(_beneficiary, wallet, _amountUsdc);

        // update state
        usdcRaised = usdcRaised + _amountUsdc;

        if (_reduction) {
            // first we compute the amount to be burned
            uint256 _amountLys = _getLysAmount(_amountUsdc);
            // then burned them by sending them to the 0xdead address
            lys.transferFrom(_beneficiary, burnAddress,_amountLys);
            // register the user in the reduced map
            reduced[_beneficiary] = _amountUsdc;
            // update the state
            lysBurned = lysBurned + _amountLys;
        } else {
            // if the user does not wish to have a reduction, register him in the notReduced map
            notReduced[_beneficiary] = notReduced[_beneficiary] = _amountUsdc;
        }

        uint256 gogoAmount = _getGogoAmount(_amountUsdc, _reduction);

        // update the gogoMapping
        gogoBalances[_beneficiary] = gogoAmount;

        // emit the event
        emit TokensPurchased(_beneficiary, _amountUsdc, gogoAmount, _reduction);
    }

    /**
     * @dev Validation of an incoming purchase. Used to require statements to revert state when conditions are not met.
     * @param _beneficiary Address performing the token purchase
     * @param _amountUsdc Value in smallest digit of usdc involved in the purchase
     */
    function _preValidatePurchase(address _beneficiary, uint256 _amountUsdc) internal view {
        require(_beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(_amountUsdc <= maxAllocation , "Crowdsale: purchase amount is too high");
        require(_amountUsdc >= minAllocation , "Crowdsale: purchase amount is too low");
        require(_amountUsdc+usdcRaised <= totalRaised , "Crowdsale: is already oversubscribed");
        require(reduced[_beneficiary] == 0 , "Crowdsale: user has already participated in a deal (with reduction)");
        require(notReduced[_beneficiary] == 0 , "Crowdsale: user already participated in a deal (without reduction)");
    }

    /**
     * @dev Computes the amount of Lys that need to be burned to be allowed to have a reduced allocation
     * @param _usdcAmount Value in smallest usdc denomination
     * @return Number of LYS tokens to be burned
     */
    function _getLysAmount(uint256 _usdcAmount) internal pure returns (uint256) {
       uint256 _tenPercentOfAllocationInUSDC = (_usdcAmount * 1) / 10;
       return (_tenPercentOfAllocationInUSDC)*7*10**12;
    }


    /**
     * @dev Computes the amount of Gogo coin that one will have
     * @param _usdcAmount Value in smallest usdc denomination
     * @return the amount of gogo coin
     */
    function _getGogoAmount(uint256 _usdcAmount, bool _reduced) internal pure returns (uint256) {
       uint256 usdcAmountEffectivelyContributed;
       if (_reduced) {
           usdcAmountEffectivelyContributed = (_usdcAmount*95)/100;
       } else {
           usdcAmountEffectivelyContributed = (_usdcAmount*70)/100;
       }
       return (usdcAmountEffectivelyContributed*1000000000000000000)/200000;
    }

    // Getters

    /**
     * @return the address where funds are collected.
     */
    function getWallet() public view returns (address) {
        return wallet;
    }

    /**
     * @return the amount of usdc raised.
     */
    function getUsdcRaised() public view returns (uint256) {
        return usdcRaised;
    }

    /**
     * @return the amount of usdc raised.
     */
    function getName() public view returns (string memory) {
        return name;
    }

    /**
     * @return the amount of usdc raised for people that did pay the reduction in Lys
     */
    function getParticipationWithReduction(address _participant) public view returns (uint256) {
        return reduced[_participant];
    }

    /**
     * @return the amount of usdc raised for people that did not pay the reduction in Lys
     */
    function getParticipationWithoutReduction(address _participant) public view returns (uint256) {
        return notReduced[_participant];
    }

    /**
     * @return the amount of gogo each user has
     */
    function getGogoAmount(address _participant) public view returns (uint256) {
        return gogoBalances[_participant];
    }

    /**
     * @return the total amount of lys burned by this contract
     */
    function getLysBurned() public view returns (uint256) {
        return lysBurned;
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
