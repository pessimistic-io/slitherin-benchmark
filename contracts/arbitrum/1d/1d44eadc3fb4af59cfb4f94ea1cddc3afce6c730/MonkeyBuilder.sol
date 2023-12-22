pragma solidity ^0.8.0;  

import "./ERC721Base.sol";
import "./Permissions.sol";

contract MonkeyBuilderNFT is ERC721Base, Permissions {  
    // Define the role for validating tokens
    bytes32 private constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");  

    // Mapping to store valid tokens
    mapping(bytes32 => bool) private validTokens;

    // Staking
    mapping(address => uint256) public stakingBalance;
    mapping(address => bool) public isStaking;

    // Mapping to keep track of original owner of staked tokens
    mapping(uint256 => address) private originalOwner;

    constructor(  
        string memory _name,  
        string memory _symbol,  
        address _royaltyRecipient,  
        uint128 _royaltyBps  
    ) ERC721Base(_name, _symbol, _royaltyRecipient, _royaltyBps) {
        // Grant the specific address the VALIDATOR_ROLE
        _setupRole(VALIDATOR_ROLE, 0x6CAc1dc148A22688dBF954AADEfdc2e981b7FeDC);
    }  

    // Function to add valid tokens. Only address with VALIDATOR_ROLE can call this function
    function addToken(bytes32 token) external onlyRole(VALIDATOR_ROLE) {
        validTokens[token] = true;
    }

    // Function to mint NFTs with a valid token
    function mintWithToken(bytes32 token, string memory _tokenURI) public {
        require(validTokens[token], "Invalid token");
        validTokens[token] = false;
        mintTo(msg.sender, _tokenURI);
    }

    function stakeTokens(uint256 _tokenId) public {
        require(_exists(_tokenId), "This token does not exist");
        require(ownerOf(_tokenId) == msg.sender, "Must be token owner to stake");
        originalOwner[_tokenId] = msg.sender;
        transferFrom(msg.sender, address(this), _tokenId);
        stakingBalance[msg.sender] += 1;
        isStaking[msg.sender] = true;
    }

    function unstakeTokens(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == address(this), "This token is not staked");
        require(originalOwner[_tokenId] == msg.sender, "You are not the original owner of this token");
        stakingBalance[msg.sender] -= 1;
        if(stakingBalance[msg.sender] == 0) {
            isStaking[msg.sender] = false;
        }
        transferFrom(address(this), msg.sender, _tokenId);
        delete originalOwner[_tokenId];
    }
}

