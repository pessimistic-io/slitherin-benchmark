// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.10;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./ISeekers.sol";
import "./IVault.sol";

/*

      /@@@#       &@@@@    /@@     @&@@@@@    ,@@            ..@@@,     @@@@@@@     @@,.@@@        &@@@@     @@@@@@@   
   @@   @@@,   /@(  @@@&   @@@   @@@&  @@@@   @@@          @@   @@@   @@@@  @@@@   @@@   @@@    (@(  @@@&  @@@@  @@@@  
  @@@   @@&   @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(  @     @@@@  @@@@  
  @@@         @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(        @@@@  @@    
  @@@         @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@&  @@@   @@@@  @@@@   @@@   @@@   @@@@@&      @@@@ @@@    
  @@@         @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(        @@@@  @@@@  
  @@@         @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(        @@@@  @@@@  
  @@@     @,  @@@(  @@@&   @@@   @@@&  @@@@   @@@         @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(    @&  @@@@  @@@@  
  @@@   @@@,  @@@(  @@@&   @@@   @@@&  @@@@   @@@   *@@   @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(  @@@&  @@@@  @@@@  
  @@@   @@@,  @@@(  @@@&   @@@   @@@&  @@@@   @@@   @@@   @@@   @@@   @@@@  @@@@   @@@   @@@   @@@(  @@@&  @@@@  @@@@  
  @@@   @     @@@(  @      @@@   @@@&  @@@@   @@@   @     @@@   @@@   @@@@  @@@@   @@@   @     @@@(  @     @@@@  @@@@  
    @@#         @@@%       @     @@    @@      ,@@.%      @     @,    @@    @@      *@@%^        @@@       @@    @@    
            
*/

contract SeasonOne is ERC1155, Ownable, ReentrancyGuard {

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                        INIT SHIT                                             //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////
    // Coin IDs
    uint256 public constant ONECOIN = 0;
    uint256 public constant SHARD = 1;

    string private _contractURI;

    // COINLANDER PARAMETERS
    address public COINLANDER;
    bool public released = false;
    bool public shardSpendable = false;
    bool private transferIsSteal = false;
    bool public gameStarted = false;
    bool public firstCommunitySoftLock = true;
    bool public secondCommunitySoftLock = true;
    uint32 public lastSeizureTime = 0;
     
    using Counters for Counters.Counter;
    Counters.Counter public seizureCount; 

    // GAME CONSTANTS
    uint256 public constant FIRSTSEEKERMINTTHRESH = 333;
    uint256 public constant CLOAKINGTHRESH = 444;
    uint256 public constant SHARDSPENDABLE = 555;
    uint256 public constant SECONDSEEKERMINTTHRESH = 666;
    uint256 public constant THIRDSEEKERMINTTHRESH = 777;
    uint256 public constant GOODSONLYEND = 888;
    uint256 public constant CLOINRELEASE = 999;
    uint256 public constant SWEETRELEASE = 1111;

    // ECONOMIC CONSTANTS  
    uint256 public constant PERCENTRATEINCREASE = 60; // 0.6% increase for each successive seizure 
    uint256 public constant PERCENTPRIZE = 100; // 1.0% of take goes to prize pool     
    uint256 constant PERCENTBASIS = 10000;
    
    // ECONOMIC STATE VARS 
    uint256 public seizureStake = 5 * 10**16; // First price for Coinlander 0.05Eth
    uint256 private previousSeizureStake = 0; 
    uint256 public prize = 0; // Prize pool balance
    uint256 private keeperShardsMinted = 0;

    // SHARD CONSTANTS
    uint256 constant KEEPERSHARDS = 111; // Keepers can mint up to 100 shards for community rewards
    uint256 constant SEEKERSHARDDROP = 1; // At least one shard to each Seeker holder 
    uint256 constant SHARDDROPRAND = 4; // Up to 3 additional shard drops (used as mod, so add 1)
    uint256 constant POWERPERSHARD = 8; // Eight power units per Shard 
    uint256 public constant SHARDTOFRAGMENTMULTIPLIER = 5; // One fragment per 5 Shards 
    uint256 constant BASESHARDREWARD = 1; // 1 Shard guaranteed per seizure
    uint256 constant INCRSHARDREWARD = 5; // .5 Eth/Shard
    uint256 constant INCRBASIS = 10; //

    // BALANCES AND ECONOMIC PARAMETERS 
    // Refund structure, tracks Eth withdraw value, earned Shard and owed Seekers 
    // value can be safely stored as a uint120
    // each seeker owed will have a unique time associated with it
    struct withdrawParams {
        uint120 _withdrawValue;
        uint16 _shardOwed;
        uint32[] _timeHeld;
    } 

    mapping(address => withdrawParams) public pendingWithdrawals;
    mapping(uint256 => bool) public claimedAirdropBySeekerId;

    struct cloinDeposit {
        address depositor; 
        uint16 amount;
        uint80 blockNumber;
    }
    cloinDeposit[] public cloinDeposits;

    ISeekers public seekers; 
    IVault private vault;

    event SweetRelease(address winner);
    event Seized(address previousOwner, address newOwner, 
            uint256 seizurePrice, uint256 nextSeizurePrice, 
            uint256 currentPrize, uint256 seizureNumber);
    event ShardSpendable();
    event NewCloinDeposit(address depositor, uint16 amount, uint256 depositIdx);
    event ClaimedAll(address claimer);
    event AirdropClaim(uint256 id);
    
    constructor(address seekersContract, address keepeersVault) ERC1155("https://api.coinlander.one/meta/season-one/{id}") {
        // Create the One Coin and set the deployer as initial COINLANDER
        _mint(msg.sender, ONECOIN, 1, "0x0");
        COINLANDER = msg.sender;

        // Add interface for seekers contract 
        seekers = ISeekers(seekersContract);
        vault = IVault(keepeersVault);

        // Set contract uri 
        _contractURI = "https://api.coinlander.one/meta/season-one";
    }

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                          MODIFIERS                                           //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    modifier postReleaseOnly() {
        require(released == true, "E-000-004");
        _;
    }

    modifier shardSpendableOnly() {
        require(shardSpendable == true, "E-000-005");
        _;
    }

    modifier validShardQty(uint256 amount) {
        require(amount > 0, "E-000-006");
        require(balanceOf(msg.sender, SHARD) >= amount, "E-000-007");
        _;
    }
    


//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                       TOKEN OVERRIDES                                        //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        // No constraints post release 
        if (!released) {
            // Check the id arry for One Coin 
            for (uint i=0; i < ids.length; i++){
                // If One Coin transfer is being attempted, check constraints 
                if (ids[i] == ONECOIN){
                    if (from != address(0) && !transferIsSteal) {
                        revert("E-000-004");
                    }
                } 
            }
        }
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
    
    function _stealTransfer(address holder, address newOwner) internal {
        transferIsSteal = true;
        _safeTransferFrom(holder, newOwner, ONECOIN, 1, "0x0"); // There is only 1 
        transferIsSteal = false;
        if (!released) {
            COINLANDER = newOwner;
        }
    }

    function changeURI(string calldata _newURI) external onlyOwner {
        _setURI(_newURI);
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string calldata newContractURI) external onlyOwner {
        _contractURI = newContractURI;
    }



//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                  COINLANDER GAME LOGIC                                       //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    function seize() external payable nonReentrant {
        require(gameStarted, "E-000-013");
        require(released == false, "E-000-001");
        require(msg.value == seizureStake, "E-000-002");
        require(msg.sender != COINLANDER, "E-000-003");

        address previousOwner = COINLANDER;
        address newOwner = msg.sender;
        
        seizureCount.increment();

        // Perform the steal
        _stealTransfer(previousOwner, newOwner);

        // Establish rewards and refunds 
        _processPaymentsAndRewards(previousOwner, previousSeizureStake);

        emit Seized(previousOwner, newOwner, msg.value, seizureStake, prize, seizureCount.current());

        // Trigger game events if price is worthy 
        _processGameEvents();
    }


    function _processPaymentsAndRewards(address previousOwner, uint256 value) internal {

        // Track time regardless of which count 
        uint32 holdTime = uint32(block.timestamp) - lastSeizureTime;
        lastSeizureTime = uint32(block.timestamp);

        // Exclude first seizure since deployer doesnt get rewards
        if (seizureCount.current() != 1) {

            // Set aside funds for prize pool
            uint256 _prize = (value * PERCENTPRIZE) / PERCENTBASIS;
            prize += _prize; 

            uint256 deposit = value - _prize;
            pendingWithdrawals[previousOwner]._withdrawValue += uint120(deposit);

            uint16 shardReward = _calculateShardReward(previousSeizureStake);
            pendingWithdrawals[previousOwner]._shardOwed += shardReward;
        }
            
        // Handle all cases except the last; the winner seeker is special cased
        if (!released) {

            // We allocate a seeker for every previous Coinlander and track the time of each hold. 
            pendingWithdrawals[previousOwner]._timeHeld.push(holdTime);

            // Store current seizure as previous
            previousSeizureStake = seizureStake;
            // Determine what it will cost to seize next time
            seizureStake = seizureStake + ((seizureStake * PERCENTRATEINCREASE) / PERCENTBASIS);
        }
    }

    // Autonomous game events triggered by Coinlander seizure count 
    function _processGameEvents() internal {
        uint256 count = seizureCount.current();

        if (count == FIRSTSEEKERMINTTHRESH) {
            seekers.activateFirstMint();
        }

        if (count == SECONDSEEKERMINTTHRESH) {
            seekers.activateSecondMint();
        }

        if (count == THIRDSEEKERMINTTHRESH) {
            seekers.activateThirdMint();
        }

        if (count == GOODSONLYEND) {
            seekers.endGoodsOnly();
        }

        if (count > THIRDSEEKERMINTTHRESH) {
            seekers.seizureMintIncrement();
        }

        if (count == CLOAKINGTHRESH) {
            seekers.performCloakingCeremony();
        }

        if (count == SHARDSPENDABLE) {
            shardSpendable = true; 
            emit ShardSpendable();
        }

        if (count == SWEETRELEASE) {
            _triggerRelease();
        }
    }

    function _triggerRelease() internal {
        released = true;
        emit SweetRelease(msg.sender);

        // Process rewards and refund for the winner 
        _processPaymentsAndRewards(msg.sender,msg.value);

        // Send prize purse to keepers vault
        vault.fundPrizePurse{value: prize}();
        vault.setSweetRelease();
        prize = 0;

        // Send winning Seeker to winner  
        seekers.sendWinnerSeeker(msg.sender);
    }

    function getSeizureCount() external view returns(uint256) {
        return seizureCount.current();
    }


//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                  IN IT TO WIN IT -- SHARD LYFE                               //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    function burnShardForPower(uint256 seekerId, uint256 amount) 
        external 
        nonReentrant 
        shardSpendableOnly 
        validShardQty(amount) {

        _burn(msg.sender, SHARD, amount);
        uint256 power = amount * POWERPERSHARD;
        seekers.addPower(seekerId, power);
    }

    function stakeShardForCloin(uint256 amount) 
        external 
        nonReentrant 
        shardSpendableOnly
        validShardQty(amount) {

        _burn(msg.sender, SHARD, amount);
        
        cloinDeposit memory _deposit;
        _deposit.depositor = msg.sender;
        _deposit.amount = uint16(amount);
        _deposit.blockNumber = uint80(block.number); 
        
        cloinDeposits.push(_deposit);
        uint256 depositsLength = cloinDeposits.length;
        emit NewCloinDeposit(msg.sender, uint16(amount), depositsLength);
    }

    function burnShardForFragments(uint256 amount) 
        external 
        nonReentrant 
        shardSpendableOnly 
        validShardQty(amount) {

        require((amount % SHARDTOFRAGMENTMULTIPLIER) == 0, "E-000-008"); // must be even multiple of the exch. rate
    
        uint256 fragmentReward = amount / SHARDTOFRAGMENTMULTIPLIER; 
        _burn(msg.sender, SHARD, amount);
        vault.requestFragments(msg.sender, fragmentReward);
    }

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                  MAGIC INTERNET MONEY BUSINESS                               //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////

    // Method for claiming all owed rewards and payments: ether refunds, shards and seekers 
    function claimAll() external nonReentrant {

        uint256 withdrawal = pendingWithdrawals[msg.sender]._withdrawValue;
        uint256 shard = pendingWithdrawals[msg.sender]._shardOwed;
        uint256 seeks = pendingWithdrawals[msg.sender]._timeHeld.length;

        if (withdrawal == 0 && shard == 0 && seeks == 0) {
            revert("E-000-010");
        }

        if (withdrawal > 0) {
            pendingWithdrawals[msg.sender]._withdrawValue = 0;
            (bool success, ) = msg.sender.call{value:withdrawal}("");
            require(success, "E-000-009");
        }

        if (shard > 0) {
            pendingWithdrawals[msg.sender]._shardOwed = 0;
            _mint(msg.sender, SHARD, shard, "0x0");

        }

        if (seeks > 0) {

            // Mint seekers 
            for (uint256 i = 0; i < seeks; i++){
                // uint32 holdTime = times[i];
                uint32 holdTime = pendingWithdrawals[msg.sender]._timeHeld[i];
                seekers.birthSeeker(msg.sender, holdTime);
            }
            delete pendingWithdrawals[msg.sender]._timeHeld;
        }

        emit ClaimedAll(msg.sender);
    }

    // Claim seeker release valve if too many in withdraw struct
    function claimSingleSeeker() external nonReentrant {
        uint256 seeks = pendingWithdrawals[msg.sender]._timeHeld.length;
        require(seeks > 0, "E-000-010");

        uint32 holdTime = pendingWithdrawals[msg.sender]._timeHeld[seeks - 1];
        pendingWithdrawals[msg.sender]._timeHeld.pop();

        seekers.birthSeeker(msg.sender, holdTime);
    }
    
    function airdropClaimBySeekerId(uint256 id) external nonReentrant postReleaseOnly {
        require(seekers.ownerOf(id) == msg.sender, "E-000-011");
        require(!claimedAirdropBySeekerId[id], "E-000-012");
        claimedAirdropBySeekerId[id] = true;
        uint256 amount;
        uint256 r1 = _getRandomNumber(SHARDDROPRAND, id);
        uint256 r2 = _getRandomNumber(SHARDDROPRAND, r1);
        amount = SEEKERSHARDDROP + r1 + r2;
        emit AirdropClaim(id);
        _mint(msg.sender, SHARD, amount, "0x0");
    }

    function keeperShardMint(uint256 amount) external onlyOwner {
        require((keeperShardsMinted + amount) <= KEEPERSHARDS);
        require(amount > 0);

        keeperShardsMinted += amount; 
        _mint(msg.sender, SHARD, amount, "0x0");
    }

    function startGame() external onlyOwner {
        gameStarted = true;
    }
    
    function _calculateShardReward(uint256 _value) private pure returns (uint16) {
        uint256 reward = BASESHARDREWARD;
        reward += (_value/10**18) * INCRBASIS / INCRSHARDREWARD;
        return uint16(reward);  
    }

    function _getRandomNumber(uint256 mod, uint256 r) private view returns (uint256) {
        uint256 random = uint256(
            keccak256(
            abi.encodePacked(
                mod,
                r,
                blockhash(block.number - 1),
                block.timestamp,
                msg.sender
                )));
        return random % mod;
    }

    function getPendingWithdrawal(address _user) external view returns (uint256[3] memory) {
        return [
            uint256(pendingWithdrawals[_user]._withdrawValue),
            uint256(pendingWithdrawals[_user]._shardOwed),
            pendingWithdrawals[_user]._timeHeld.length
        ];
    }

    function getAirdropStatus(uint256 _id) external view returns (bool) {
        return claimedAirdropBySeekerId[_id];
    }

    // If someone messes up and pays us without using the seize method, revert 
    receive() external payable {
        revert("E-000-009");
    }
}
