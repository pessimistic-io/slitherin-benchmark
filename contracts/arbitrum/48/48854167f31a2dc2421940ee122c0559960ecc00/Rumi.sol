// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;


import "./IERC165Upgradeable.sol";
import "./Initializable.sol";
import "./OFTUpgradeable.sol";

contract Rumi is Initializable, OFTUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
    
    //Review if these values should be variable over time
    uint256 constant public initialSupply = 566 * 10**18;    
    uint256 constant public maxTokenSupply = 102334155*10**18;
    
    

    address private presaleContractAddress;
    bool private approvePresaleContractIsAllowed;
    uint256 public counter = 0;    
    function initialize(string memory _name, string memory _symbol, address _lzEndpoint)public initializer {                                
       __OFTUpgradeable_init(_name, _symbol, _lzEndpoint);
        approvePresaleContractIsAllowed = true;         
    }    

    function mintTokensToOwner() external onlyOwner {        
        _mint(msg.sender, 10 * 10**decimals());       
    }
    
    /* CONVERT MULTICHAIN*/

    /**
     * @dev Sets presale contract address. It is called automatically right after presale contract is deployed.
     */
    function setPresaleContractAddress(address _presaleContractAddress) external onlyOwner returns (address) {
        require(presaleContractAddress == address(0), "Address already initialized");
        presaleContractAddress =_presaleContractAddress;
        return presaleContractAddress;
    }

    /**
     * @dev Approves presale contract to transfer initial tokens on your behalf
     */
    function mintToPresaleContract(uint256 _amount) external returns (bool) {
        require(msg.sender == presaleContractAddress, "Caller should be presale");        
        require(approvePresaleContractIsAllowed, "Approval to presale contract is not allowed anymore");        
        _mint(getPresaleContractAddress(), _amount);
        approvePresaleContractIsAllowed = false;
        return true;
    }

     /**
     * @dev Burns presale contract excess balance
     */
    function burnToPresaleContract(uint256 _amount) external returns (bool) {
        require(msg.sender == presaleContractAddress, "Caller should be presale");                
        _burn(getPresaleContractAddress(), _amount);        
        return true;
    }    

    function getPresaleContractAddress() public view returns (address) {
        return presaleContractAddress;
    }

    //TODO
    //WHITELIST TRANSFER FUNCTION

    //TODO
    //STAKING CONTRACT
    /* RECEIVE REWARDS - RUMI TOKENS*/
}
