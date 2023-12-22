// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC721.sol";
import "./EnumerableMap.sol";
import "./ECDSA.sol";


contract ChivalryToken is ERC20, Ownable {
    uint8 private constant _decimals = 18;
    uint256 public constant MAX_SUPPLY = 777000000000 * (10 ** uint256(_decimals));
    bool private _burnEnabled = true;
    uint256 public constant MIN_TRANSFER_AMOUNT = 1000 * (10 ** uint256(_decimals));
    uint256 public MAX_TRANSFER_AMOUNT = 7777777 * (10 ** uint256(_decimals));
    uint256 public constant MAX_HOLDING_AMOUNT = 77777777 * (10 ** uint256(_decimals));
    uint256 public constant MIN_TRANSFER_INTERVAL = 777 seconds;
    uint256 public constant MIN_VOTE_COUNT = 100;
    uint256 public constant KNIGHT_NFT_ID = 1;
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 private constant VOTE_TYPEHASH = keccak256("Vote(address nominee,uint256 deadline)");
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    mapping(address => bytes32) private _committedVotes;

    EnumerableMap.AddressToUintMap private _nominatedKnightsMap;

    
    mapping (address => uint256) private _lastTransferTimestamp;
    mapping (address => bool) private _nominatedKnights;
    mapping (address => bool) private _voted;
    address public currentKnight;
    uint256 public currentVotes;
    ERC721 private _nft;
    
    event MaxTransferAmountChanged(uint256 newMaxAmount);
    event BurnEnabledChanged(bool enabled);
    event KnightNominated(address indexed nominee);
    event KnightElected(address indexed newKnight);
    event VoteCountReset(address indexed voter);
    
    constructor(address nftAddress) ERC20("ChivalryToken", "CHIVA") {
        // Set initial supply of 777 billion tokens
        _transferOwnership(msg.sender);
        _mint(msg.sender, MAX_SUPPLY);
        _nft = ERC721(nftAddress);
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        // Remove the minimum transfer amount check
        //require(amount >= MIN_TRANSFER_AMOUNT, "Transfer amount must be at least 1000 CHIVA");
        require(amount <= MAX_TRANSFER_AMOUNT, "Transfer amount exceeds maximum transfer amount");
        //require(balanceOf(msg.sender) - amount <= MAX_HOLDING_AMOUNT, "Sender cannot hold more than 77,777,777 CHIVA after the transfer");
        require(_lastTransferTimestamp[msg.sender] == 0 || block.timestamp - _lastTransferTimestamp[msg.sender] >= MIN_TRANSFER_INTERVAL, "Sender must wait at least 777 seconds between transfers");
        
        uint256 transferAmount = amount;
        if (_burnEnabled) {
            uint256 burnAmount = amount / 10;
            transferAmount = amount - burnAmount;
            _burn(msg.sender, burnAmount);
        }
        
        _transfer(msg.sender, recipient, transferAmount);
        
        _lastTransferTimestamp[msg.sender] = block.timestamp;
        
        return true;
    }
    
    function enableBurn() public onlyOwner {
        _burnEnabled = true;
        emit BurnEnabledChanged(true);
    }
    
    function disableBurn() public onlyOwner {
        _burnEnabled = false;
        emit BurnEnabledChanged(false);
    }
    
    function isBurnEnabled() public view returns (bool) {
        return _burnEnabled;
    }
    
    function setMaxTransferAmount(uint256 newMaxAmount) public onlyOwner {
        require(newMaxAmount > 0, "Maximum transfer amount must be greater than 0");
        MAX_TRANSFER_AMOUNT = newMaxAmount;
        emit MaxTransferAmountChanged(newMaxAmount);
    }

       function nominateKnight() public {
        // check if user is eligible to be nominated
        require(balanceOf(msg.sender) >= MIN_VOTE_COUNT * (10 ** uint256(_decimals)), "Nominee must hold at least 100 votes worth of CHIVA");
        require(!_nominatedKnights[msg.sender], "Nominee has already been nominated");
        
        // nominate the user as a potential knight
        _nominatedKnightsMap.set(msg.sender, 0);
        
        // emit event
        emit KnightNominated(msg.sender);
    }


    function resetVoteCount() public {
        require(_voted[msg.sender], "Sender has not voted before");
        
        // reset vote count for user
        _voted[msg.sender] = false;
        
        // emit event
        emit VoteCountReset(msg.sender);
    }

    // Add a commitVote function that accepts the hash of the vote
    function commitVote(bytes32 voteHash) public {
        require(_committedVotes[msg.sender] == 0, "Sender has already committed a vote");
        _committedVotes[msg.sender] = voteHash;
    }
    
    function electKnight() public onlyOwner {
        // find the nominee with the most votes
        uint256 highestVoteCount = 0;
        address highestVoteAddress = address(0);
        address[] memory nominees = getNominees();
        for (uint256 i = 0; i < nominees.length; i++) {
            address nominee = nominees[i];
            uint256 voteCount = balanceOf(nominee);
            if (voteCount > highestVoteCount) {
                highestVoteCount = voteCount;
                highestVoteAddress = nominee;
            }
        }
        
        // transfer knight NFT to the new knight
        if (highestVoteAddress != address(0)) {
            _nft.transferFrom(address(this), highestVoteAddress, KNIGHT_NFT_ID);
        }
        
        // set the new knight and reset vote counts
        currentKnight = highestVoteAddress;
        currentVotes = highestVoteCount;
        for (uint256 i = 0; i < nominees.length; i++) {
            address nominee = nominees[i];
            _voted[nominee] = false;
        }
        
        // emit event
        emit KnightElected(currentKnight);
    }

        function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
        chainId := chainid()
        }
        return chainId;
        }

    
        // Update the vote function to accept the revealed vote and compare it to the committed vote
    function vote(address nominee, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(_nominatedKnightsMap.contains(nominee), "Nominee has not been nominated");
        require(!_voted[msg.sender], "Sender has already voted");

        bytes32 voteHash = keccak256(abi.encodePacked(nominee, deadline, v, r, s));
        require(_committedVotes[msg.sender] == voteHash, "Vote does not match the committed vote");

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, nominee, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ECDSA.recover(digest, v, r, s);
        require(signer != address(0) && signer == msg.sender, "Invalid signature");

        _transfer(msg.sender, nominee, 1 * (10 ** uint256(_decimals)));

        _voted[msg.sender] = true;
    }

    
    function getNominees() public view returns (address[] memory) {
    uint256 nomineeCount = 0;
    for (uint256 i = 0; i < _nominatedKnightsMap.length(); i++) {
        (address nominee, ) = _nominatedKnightsMap.at(i);
        if (balanceOf(nominee) >= MIN_VOTE_COUNT * (10 ** uint256(_decimals))) {
            nomineeCount++;
        }
    }
    address[] memory nominees = new address[](nomineeCount);
    uint256 j = 0;
    for (uint256 i = 0; i < _nominatedKnightsMap.length(); i++) {
        (address nominee, ) = _nominatedKnightsMap.at(i);
        if (balanceOf(nominee) >= MIN_VOTE_COUNT * (10 ** uint256(_decimals))) {
            nominees[j] = nominee;
            j++;
        }
    }
    return nominees;
}

}
