// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.10;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IVault.sol";

contract Vault is IVault, ERC1155, Ownable, ReentrancyGuard {

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                        INIT SHIT                                             //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    // Coin IDs
    uint256 public constant KEY = 0;
    uint256 public constant FRAGMENT1 = 1;
    uint256 public constant FRAGMENT2 = 2;
    uint256 public constant FRAGMENT3 = 3;
    uint256 public constant FRAGMENT4 = 4;
    uint256 public constant FRAGMENT5 = 5;
    uint256 public constant FRAGMENT6 = 6;
    uint256 public constant FRAGMENT7 = 7;
    uint256 public constant FRAGMENT8 = 8;

    // FRAGMENT PARAMETERS
    uint16 public constant MAXFRAGMENTS = 1111;
    uint16[] private fragments; // Dynamic array of all fragment ids

    // Max supply of each type 
    uint16 public constant numT1 = 3;
    uint16 public constant numT2 = 10;
    uint16 public constant numT3 = 10;
    uint16 public constant numT4 = 50;
    uint16 public constant numT5 = 100;
    uint16 public constant numT6 = 111;
    uint16 public constant numT7 = 222;
    uint16 public constant numT8 = MAXFRAGMENTS - numT1 - numT2 - numT3 - numT4 - numT5 - numT6 - numT7;

    uint256 public prize = 0; 
    bool public gameWon = false;
    bool public sweetRelease = false;
    address public gameContract = address(0);
    string private _contractURI;

    // RANDOMNESS ORACLE VARS
    address public randomnessOracle;
    uint16 public requestId;
    uint16 pendingRequests;
    struct fulfillmentState {
        bool fulfilled;
        address requester;
    }
    mapping(address => uint16[]) public claimables;
    mapping(uint16 => fulfillmentState) public requestFulfillments;


    // @TODO we need to figure out what the url schema for metadata looks like and plop that here in the constructor
    constructor(address _randomnessOracle) ERC1155("https://api.coinlander.one/meta/vault/{id}") {

        // Initialize the fragments array
        for  (uint16 i = 0; i < numT1; i++){
            fragments.push(uint16(FRAGMENT1));
        }
        for  (uint16 i = 0; i < numT2; i++){
            fragments.push(uint16(FRAGMENT2));
        }
        for  (uint16 i = 0; i < numT3; i++){
            fragments.push(uint16(FRAGMENT3));
        }
        for  (uint16 i = 0; i < numT4; i++){
            fragments.push(uint16(FRAGMENT4));
        }
        for  (uint16 i = 0; i < numT5; i++){
            fragments.push(uint16(FRAGMENT5));
        }
        for  (uint16 i = 0; i < numT6; i++){
            fragments.push(uint16(FRAGMENT6));
        }
        for  (uint16 i = 0; i < numT7; i++){
            fragments.push(uint16(FRAGMENT7));
        }
        for  (uint16 i = 0; i < numT8; i++){
            fragments.push(uint16(FRAGMENT8));
        }

        _contractURI = "https://api.coinlander.one/meta/vault";
        randomnessOracle = _randomnessOracle;
    }

    modifier onlyRandomnessOracle() {
        require(msg.sender == randomnessOracle, "E-002-0016");
        _;
    }
    
    modifier onlyGameContract {
        require(msg.sender == gameContract, "E-002-015");
        _;
    }

    function requestFragments(address _requester, uint256 amount) external onlyGameContract {
        require((fragments.length - pendingRequests) >= amount, "E-002-009");
        for(uint256 i = 0; i < amount; i++){
            requestId++;
            pendingRequests++;
            emit RandomnessRequested(_requester, requestId);
            requestFulfillments[requestId].requester = _requester;
        }
    }

    function fulfillRequest(uint16 _requestId) external onlyRandomnessOracle {
        require(!requestFulfillments[_requestId].fulfilled, "E-002-017");
        require(pendingRequests > 0, "E-002-019");
        require(_requestId <= requestId, "E-002-020");

        requestFulfillments[_requestId].fulfilled = true;
        pendingRequests--;

        uint256 random = _getRandomNumber(fragments);
        uint16 fragType = fragments[random];

        fragments[random] = fragments[fragments.length - 1]; 
        fragments.pop();

        address requester = requestFulfillments[_requestId].requester;
        claimables[requester].push(fragType);

        emit RandomnessFulfilled(_requestId, fragType);
    }

    function claimFragments() external nonReentrant {
        require(claimables[msg.sender].length > 0, "E-002-018");

        for(uint256 i = 0; i < claimables[msg.sender].length; i++){
            uint256 fragmentType = uint256(claimables[msg.sender][i]);
            _mint(msg.sender, fragmentType, 1, "0x0");
        }

        delete claimables[msg.sender];
    }

    function getClaimablesByAddress(address user) view external returns(uint256) {
        return claimables[user].length;
    }

    function setSweetRelease() external onlyGameContract {
        sweetRelease = true;
    }

    function claimKeepersVault() external nonReentrant {
        require(sweetRelease, "E-002-010");
        require(!gameWon, "E-002-011");
        require(prize > 0, "E-002-012");
        require(balanceOf(msg.sender, FRAGMENT1) > 0, "E-002-001");
        require(balanceOf(msg.sender, FRAGMENT2) > 0, "E-002-002");
        require(balanceOf(msg.sender, FRAGMENT3) > 0, "E-002-003");
        require(balanceOf(msg.sender, FRAGMENT4) > 0, "E-002-004");
        require(balanceOf(msg.sender, FRAGMENT5) > 0, "E-002-005");
        require(balanceOf(msg.sender, FRAGMENT6) > 0, "E-002-006");
        require(balanceOf(msg.sender, FRAGMENT7) > 0, "E-002-007");
        require(balanceOf(msg.sender, FRAGMENT8) > 0, "E-002-008");

        // Assemble the Key 
        _burn(msg.sender, FRAGMENT1, 1);
        _burn(msg.sender, FRAGMENT2, 1);
        _burn(msg.sender, FRAGMENT3, 1);
        _burn(msg.sender, FRAGMENT4, 1);
        _burn(msg.sender, FRAGMENT5, 1);
        _burn(msg.sender, FRAGMENT6, 1);
        _burn(msg.sender, FRAGMENT7, 1);
        _burn(msg.sender, FRAGMENT8, 1);
        _mint(msg.sender, KEY, 1, "0x0");

        // Unlock the vault
        emit VaultUnlocked(msg.sender);
        gameWon = true;
        uint256 _prize = prize;
        prize = 0;
        (bool success, ) = msg.sender.call{value:_prize}("");
        require(success, "E-002-014");
    }
    
    function fundPrizePurse() payable public {
        prize += msg.value;
    }

    // Thanks Manny - entropy is a bitch
    function _getRandomNumber(uint16[] storage _arr) private view returns (uint256) {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    _arr,
                    blockhash(block.number - 1),
                    msg.sender
                )
            )
        );
        return (random % _arr.length);
    }

    function setGameContract(address _gameContract) external onlyOwner {
        gameContract = _gameContract; 
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        _contractURI = newContractURI;
    }

    function changeURI(string calldata _newURI) external onlyOwner {
        _setURI(_newURI);
    }

    function setRandomnessOracle(address newOracle) external onlyOwner {
        emit RandomnessOracleChanged(randomnessOracle, newOracle);
        randomnessOracle = newOracle;
    }

    // All fund allocations should be going thru fund prize purse
    receive() external payable {
        revert("E-002-014");
    }
}
