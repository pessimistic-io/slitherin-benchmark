// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./OwnableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./console.sol";

contract MessageValidator is OwnableUpgradeable {
    
    event GalaWalletAddressSet(address galaWalletAddress);  
    event ValidWalletAddressAdded(address walletAddress);     
    event ValidWalletAddressRemoved(address walletAddress);    
    event ImportantAddressSet(address importantAddress); 
    event BlockMaxThresholdSet(uint blockMaxThreshold);
    
    using ECDSAUpgradeable for bytes32; 
    address public galaWallet; 
    address public importantAddress; 
    uint256 public blockMaxThreshold;  
    mapping(string => bool) orders;
    mapping(address => bool) public validWallets;    
     uint256[50] private  __gap;   

    struct PaymentMessage {
        string orderId;
        address token;
        uint256 amount;
        uint256 transBlock;
        uint256 transType;
        string systemName;
        uint256 chainId;
        address wallet;
        bytes sig;        
    }

    struct PaymentMessageEth
    {
        string orderId;        
        uint amount;
        uint transBlock;  
        string systemName;      
        uint256 chainId;
        address wallet;
        bytes sig;        
        
    }

    struct PaymentMessageErc1155 {
        string orderId;
        address token;
        uint256 baseId;
        uint256 amount;
        uint256 transBlock;
        uint256 transType;
        string systemName;
        uint256 chainId;        
        bytes sig;        
    }   
     
    

    function setGalaWalletAddress(address _galaWalletAddress)
        external
        onlyOwner
    {
        require(
            _galaWalletAddress != address(0),
            "Wallet address cannot be zero"
        );
        emit GalaWalletAddressSet(_galaWalletAddress);
        galaWallet = _galaWalletAddress;
    }

    function addValidWalletAddress(address validWalletAddress) external onlyOwner {            
        require(validWalletAddress != address(0), "Wallet address cannot be zero");
        emit ValidWalletAddressAdded(validWalletAddress);     
        validWallets[validWalletAddress] = true;
    }

    function removeValidWalletAddress(address validWalletAddress) external onlyOwner {            
        require(validWalletAddress != address(0), "Wallet address cannot be zero");
        emit ValidWalletAddressRemoved(validWalletAddress);     
        delete validWallets[validWalletAddress];
    }

     function setImportantAddress(address _importantAddress) external onlyOwner {    
        require(_importantAddress != address(0), "important address cannot be zero");    
        emit ImportantAddressSet(_importantAddress); 
        importantAddress = _importantAddress;       
    }

    function setBlockMaxThreshold(uint256 _blockMaxThreshold)
        external
        onlyOwner
    {
        require(
            _blockMaxThreshold != 0,
            "blockMax threshold must be greater than zero"
        );
        emit BlockMaxThresholdSet(_blockMaxThreshold);
        blockMaxThreshold = _blockMaxThreshold;
    }

    modifier isValidMessage(PaymentMessage calldata _params)
    {   
        bytes32 message = keccak256(abi.encodePacked(_params.orderId, _params.token, _params.amount, _params.transBlock, _params.transType, _params.systemName, _params.chainId, _params.wallet));        
        require(message.recover(_params.sig) == importantAddress, "Token Invalid signature");       
        require(_params.chainId == getChainId(), "Invalid Chain"); 
        _;    
    }   

     modifier isValidMessageForEth(PaymentMessageEth calldata _params)
    {        
        bytes32 message = keccak256(abi.encodePacked(_params.orderId, _params.amount, _params.transBlock, _params.systemName, _params.chainId, _params.wallet));        
        require(message.recover(_params.sig) == importantAddress, "Eth Invalid signature");         
        require(_params.amount  == msg.value, "Invalid Amount");       
        require(_params.chainId == getChainId(), "Invalid Chain");   
        _;    
    }  

    modifier isValidMessageForErc1155(PaymentMessageErc1155 calldata _params) 
    {        
        bytes32 message = keccak256(abi.encodePacked(_params.orderId, _params.token, _params.baseId, _params.amount, _params.transBlock, _params.transType, _params.systemName, _params.chainId));                                            
        require(message.recover(_params.sig) == importantAddress, "ERC1155 Token Invalid signature");   
        require(_params.chainId == getChainId(), "Invalid Chain");       
        _;    
    }   

    modifier isValidBlock(uint256 _transBlock) {
        require(
            block.number <= _transBlock + blockMaxThreshold,
            "block exceeded the threshold"
        );
        _;
    }

    modifier isValidOrder(string memory _orderId) {
        require(!orders[_orderId], "duplicate order");
        orders[_orderId] = true;
        _;
   }  

    
    modifier isValidWallet(address _wallet) {
        require(_wallet == address(0) || validWallets[_wallet], "Wallet address can either be zero or a valid address");
        _;
    }
    
    function getChainId() private view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}

