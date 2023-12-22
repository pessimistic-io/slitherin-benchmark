// SPDX-License-Identifier: MIT
// Metaline Contracts (Expedition.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./MTT.sol";
import "./MTTGold.sol";
import "./HeroNFT.sol";
import "./WarrantNFT.sol";
import "./ShipNFT.sol";
import "./HeroNFTCodec.sol";
import "./NFTAttrSource.sol";

import "./MTTMinePool.sol";

contract Expedition is
    Context,
    Pausable,
    AccessControl,
    IERC721Receiver
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event SetHeroExpedTeam(address indexed userAddr, uint16 indexed portID, uint256 teamHashRate, uint256[] heroNftIDs);
    event UnsetHeroExpedTeam(address indexed userAddr, uint16 indexed portID, uint256 teamHashRate, uint256[] heroNftIDs);

    event SetShipExpedTeam(address indexed userAddr, uint16 portID, uint256 teamHashRate, ExpeditionShip[] expedShips);
    event UnsetShipExpedTeam(address indexed userAddr, uint16 portID, uint256 teamHashRate, ExpeditionShip[] expedShips);

    event OutputMTT(uint256 value, ExpeditionPoolData poolData);
    event StartExpedition(address indexed userAddr, ExpeditionTeamData teamData, ExpeditionPoolData poolData);
    event FetchExpeditionMTT(address indexed userAddr, uint256 value, ExpeditionTeamData teamData, ExpeditionPoolData poolData);

    struct ExpeditionPoolConf {
        uint256 minHashRate; // expedition team minimum hashrate require
        uint256 maxHashRate; // expedition team maximum hashrate allowed

        uint256 minBlockInterval; // each expedition spend bocklInterval time, 
        uint256 goldPerHashrate; // allow input gold by 1 hashrate when expedition blocks = minBlockInterval, 18 decimal
        
        uint256 maxMTTPerGold; // limit max mtt output per gold, 8 decimals, mtt = gold * mttpergold/100000000

        uint256 minMTTPerBlock; // min MTT output per block, no matter how many hashrate in this pool
        uint256 maxMTTPerBlock; // max MTT output per block, even more than maxOutputhashRate hashrate in this pool
        uint256 maxOutputhashRate; // MTT output = min(maxMTTPerBlock, max(minMTTPerBlock, maxMTTPerBlock*totalHashRate/maxOutputhashRate))
    }

    struct ExpeditionTeamData {
        uint256 inputGoldLeft;
        uint256 expedLastFetchBlock;
        uint256 goldPerBlock;
        uint256 expedEndBlock;
    }
    struct ExpeditionPoolData {
        uint256 totalHashRate; // all team hashrate
        uint256 totalOutputMTT; // total output MTT
        uint256 totalInputGold; // total input gold
        uint256 currentOutputMTT; // current output mtt
        uint256 currentInputGold; // current input gold

        uint256 currentMTTPerBlock; // current mtt output per block
        uint256 lastOutputBlock; // last output mtt block number
    }

    struct ExpeditionShip {
        uint256 shipNFTID;
        uint256[] heroNFTIDs;
    }
    struct ShipExpeditionTeam {
        uint256 teamHashRate;
        ExpeditionShip[] ships;

        ExpeditionTeamData teamData;
    }

    struct HeroExpeditionTeam {
        uint256 teamHashRate; // all nft hashrate
        uint256[] heroNFTIDs; // hero nfts, 0 must be hero nft

        ExpeditionTeamData teamData;
    }

    struct PortHeroExpedPool {
        ExpeditionPoolData poolData;
        ExpeditionPoolConf poolConf; 
        mapping(address=>HeroExpeditionTeam) expedHeros; // user addr => hero expedition team
    }

    struct PortShipExpedPool {
        ExpeditionPoolData poolData;
        ExpeditionPoolConf poolConf; 
        mapping(address=>ShipExpeditionTeam) expedShips; // user addr => ship expedition team
    }

    address public _warrantNFTAddr;
    address public _heroNFTAddr;
    address public _shipNFTAddr;
    address public _MTTGoldAddr;
    address public _MTTAddr;
    address public _MTTMinePoolAddr;

    mapping(uint16=>PortHeroExpedPool) public _heroExpeditions;
    mapping(uint16=>PortShipExpedPool) public _shipExpeditions;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "Expedition: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "Expedition: must have pauser role to unpause"
        );
        _unpause();
    }

    function init(
        address warrantNFTAddr,
        address heroNFTAddr,
        address shipNFTAddr,
        address MTTAddr,
        address MTTGoldAddr,
        address MTTMinePoolAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Expedition: must have manager role");

        _warrantNFTAddr = warrantNFTAddr;
        _heroNFTAddr = heroNFTAddr;
        _shipNFTAddr = shipNFTAddr;
        _MTTAddr = MTTAddr;
        _MTTGoldAddr = MTTGoldAddr;
        _MTTMinePoolAddr = MTTMinePoolAddr;
    }

    function setPortHeroExpedConf(uint16 portID, ExpeditionPoolConf memory conf) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Expedition: must have manager role");

        _heroExpeditions[portID].poolConf = conf;
    }
    function setPortShipExpedConf(uint16 portID, ExpeditionPoolConf memory conf) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Expedition: must have manager role");

        _shipExpeditions[portID].poolConf = conf;
    }

    function getHeroExpedData(uint16 portID, address userAddr) external view returns (HeroExpeditionTeam memory) {
        return _heroExpeditions[portID].expedHeros[userAddr];
    }
    function getShipExpedData(uint16 portID, address userAddr) external view returns (ShipExpeditionTeam memory) {
        return _shipExpeditions[portID].expedShips[userAddr];
    }

    function setHeroExpedTeam(uint16 portID, uint256[] memory heroNftIDs) external {

        PortHeroExpedPool storage phep = _heroExpeditions[portID];
        require(phep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        require(heroNftIDs.length > 0, "Expedition: team hero must >0");

        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());
        NFTAttrSource_V1 attSrc = NFTAttrSource_V1(HeroNFT(_heroNFTAddr).getAttrSource());

        uint256 teamHashRate = 0;
        uint8 leadGrade = 0;
        for(uint i=0; i<heroNftIDs.length; ++i){
            require(HeroNFT(_heroNFTAddr).ownerOf(heroNftIDs[i]) == _msgSender(), "Expedition: not your hero or pet");

            HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(heroNftIDs[i]);

            if(i==0){
                // must be hero nft
                require(hdb.nftType == 1, "Expedition: team leader must be hero"); 
            }

            if(hdb.nftType == 1) { // hero 
                HeroNFTFixedData_V1 memory hndata = codec.getHeroNftFixedData(hdb);
                HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);

                if(i==0){
                    leadGrade = hndata.grade;
                    require(wdata.starLevel+1 >= heroNftIDs.length, "Expedition: team leader star level must >= team hero count"); 
                }
                else {
                    require(hndata.grade <= leadGrade, "Expedition: team member grade must <= leader grade");
                }

                HeroNFTMinerAttr memory hmattr = attSrc.getHeroMinerAttr(hndata.minerAttr, wdata.starLevel);
                teamHashRate += hmattr.hashRate;
            } 
            else if(hdb.nftType == 2) { // pet
                HeroPetNFTFixedData_V1 memory hndata = codec.getHeroPetNftFixedData(hdb);
                
                HeroNFTMinerAttr memory hmattr = attSrc.getHeroMinerAttr(hndata.minerAttr, 1);
                teamHashRate += hmattr.hashRate;
            }
            else {
                revert("Expedition: nft type error");
            }

            // transfer hero into pool
            HeroNFT(_heroNFTAddr).safeTransferFrom(_msgSender(), address(this), heroNftIDs[i]);
        }

        require(teamHashRate > phep.poolConf.minHashRate, "Expedition: team hashrate not enough");
        require(teamHashRate <= phep.poolConf.maxHashRate, "Expedition: team hashrate overflow");

        phep.expedHeros[_msgSender()] = HeroExpeditionTeam({
            teamHashRate:teamHashRate,
            heroNFTIDs:heroNftIDs,
            teamData:ExpeditionTeamData({
                inputGoldLeft:0,
                expedLastFetchBlock:0,
                goldPerBlock:0,
                expedEndBlock:0
            })
        });
        
        // output mtt
        _outputMTT(phep.poolData);

        // add pool total hashrate
        phep.poolData.totalHashRate += teamHashRate;
        
        // recalc output mtt per block
        _calcOutputMTTPerBlock(phep.poolConf, phep.poolData);

        emit SetHeroExpedTeam(_msgSender(), portID, teamHashRate, heroNftIDs);
    }

    function unsetHeroExpedTeam(uint16 portID) external {
        
        PortHeroExpedPool storage phep = _heroExpeditions[portID];
        require(phep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        HeroExpeditionTeam storage team = phep.expedHeros[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");

        for(uint i=0; i<team.heroNFTIDs.length; ++i){
            // send back hero
            HeroNFT(_heroNFTAddr).safeTransferFrom(address(this), _msgSender(), team.heroNFTIDs[i]);
        }

        require(phep.poolData.totalHashRate >= team.teamHashRate, "Expedition: total hashrate underflow");
        
        // output mtt
        _outputMTT(phep.poolData);
        
        // sub pool total hashrate
        phep.poolData.totalHashRate -= team.teamHashRate;
        
        // recalc output mtt per block
        _calcOutputMTTPerBlock(phep.poolConf, phep.poolData);

        emit UnsetHeroExpedTeam(_msgSender(), portID, team.teamHashRate, team.heroNFTIDs);

        delete phep.expedHeros[_msgSender()];
    }

    function setShipExpedTeam(uint16 portID, ExpeditionShip[] memory expedShips) external {

        PortShipExpedPool storage psep = _shipExpeditions[portID];
        require(psep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");

        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());
        NFTAttrSource_V1 attSrc = NFTAttrSource_V1(HeroNFT(_heroNFTAddr).getAttrSource());
        NFTAttrSource_V1 sattSrc = NFTAttrSource_V1(ShipNFT(_shipNFTAddr).getAttrSource());

        ShipExpeditionTeam storage shipet = psep.expedShips[_msgSender()];
        uint8 flagShipGrade = 0;
        for(uint j=0; j< expedShips.length; ++j){
            require(ShipNFT(_shipNFTAddr).ownerOf(expedShips[j].shipNFTID) == _msgSender(), "Expedition: not your ship");

            ShipNFTData memory sd = ShipNFT(_shipNFTAddr).getNftData(expedShips[j].shipNFTID);
            ShipNFTMinerAttr memory smattr = sattSrc.getShipMinerAttr(sd.minerAttr, sd.level);
            require(smattr.maxSailer >= expedShips[j].heroNFTIDs.length);
            shipet.teamHashRate += smattr.hashRate;

            require(sd.shipType == 1, "Expedition: not cargo ship");

            if(j==0){
                require((sd.level / 10)+1 >= expedShips.length, "Expedition: flag ship level/10 must >= team ships count");
                flagShipGrade = sd.grade;
            }
            else {
                require(sd.grade <= flagShipGrade, "Expedition: flag ship grade must >= team ship grade");
            }

            // transfer ship into pool
            ShipNFT(_shipNFTAddr).safeTransferFrom(_msgSender(), address(this), expedShips[j].shipNFTID);

            for(uint i=0; i<expedShips[j].heroNFTIDs.length; ++i){
                require(HeroNFT(_heroNFTAddr).ownerOf(expedShips[j].heroNFTIDs[i]) == _msgSender(), "Expedition: not your hero or pet");

                HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(expedShips[j].heroNFTIDs[i]);

                if(i==0){
                    // must be hero nft
                    require(hdb.nftType == 1, "Expedition: captain must be hero"); 
                }

                if(hdb.nftType == 1) { // hero 
                    HeroNFTFixedData_V1 memory hndata = codec.getHeroNftFixedData(hdb);
                    HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);

                    HeroNFTMinerAttr memory hmattr = attSrc.getHeroMinerAttr(hndata.minerAttr, wdata.starLevel);
                    shipet.teamHashRate += hmattr.hashRate;
                } 
                else if(hdb.nftType == 2) { // pet
                    HeroPetNFTFixedData_V1 memory hndata = codec.getHeroPetNftFixedData(hdb);
                    
                    HeroNFTMinerAttr memory hmattr = attSrc.getHeroMinerAttr(hndata.minerAttr, 1);
                    shipet.teamHashRate += hmattr.hashRate;
                }
                else {
                    revert("Expedition: nft type error");
                }

                // transfer hero into pool
                HeroNFT(_heroNFTAddr).safeTransferFrom(_msgSender(), address(this), expedShips[j].heroNFTIDs[i]);
            }

            shipet.ships.push(expedShips[j]);
        }

        require(shipet.teamHashRate > psep.poolConf.minHashRate, "Expedition: team hashrate not enough");
        require(shipet.teamHashRate <= psep.poolConf.maxHashRate, "Expedition: team hashrate overflow");

        shipet.teamData = ExpeditionTeamData({
            inputGoldLeft:0,
            expedLastFetchBlock:0,
            goldPerBlock:0,
            expedEndBlock:0
        });
        
        // output mtt
        _outputMTT(psep.poolData);

        // add pool total hashrate
        psep.poolData.totalHashRate += shipet.teamHashRate;
        
        // recalc output mtt per block
        _calcOutputMTTPerBlock(psep.poolConf, psep.poolData);

        emit SetShipExpedTeam(_msgSender(), portID, shipet.teamHashRate, expedShips);
    }
    function unsetShipExpedTeam(uint16 portID) external {
        PortShipExpedPool storage psep = _shipExpeditions[portID];
        require(psep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        ShipExpeditionTeam storage team = psep.expedShips[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");

        for(uint j=0; j<team.ships.length; ++j){
            // send back ship
            ShipNFT(_shipNFTAddr).safeTransferFrom(address(this), _msgSender(), team.ships[j].shipNFTID);

            for(uint i=0; i<team.ships[j].heroNFTIDs.length; ++i){
                // send back hero
                HeroNFT(_heroNFTAddr).safeTransferFrom(address(this), _msgSender(), team.ships[j].heroNFTIDs[i]);
            }
        }

        require(psep.poolData.totalHashRate >= team.teamHashRate, "Expedition: total hashrate underflow");

        // output mtt
        _outputMTT(psep.poolData);

        // sub pool total hashrate
        psep.poolData.totalHashRate -= team.teamHashRate;

        // recalc output mtt per block
        _calcOutputMTTPerBlock(psep.poolConf, psep.poolData);

        emit UnsetShipExpedTeam(_msgSender(), portID, team.teamHashRate, team.ships);

        delete psep.expedShips[_msgSender()];
    }

    function _calcOutputMTTPerBlock(
        ExpeditionPoolConf storage conf,
        ExpeditionPoolData storage poolData
    ) internal {
        poolData.currentMTTPerBlock = conf.maxMTTPerBlock * poolData.totalHashRate / conf.maxOutputhashRate;
        if(poolData.currentMTTPerBlock < conf.minMTTPerBlock) {
            poolData.currentMTTPerBlock = conf.minMTTPerBlock;
        }
        else if(poolData.currentMTTPerBlock > conf.maxMTTPerBlock) {
            poolData.currentMTTPerBlock = conf.maxMTTPerBlock;
        }
    }

    function _outputMTT(
        ExpeditionPoolData storage poolData
    ) internal {
        if(poolData.lastOutputBlock == 0){
            poolData.lastOutputBlock = block.number;
            return;
        }
        if(poolData.totalHashRate == 0){
            poolData.lastOutputBlock = block.number;
            return;
        }
        if(poolData.lastOutputBlock >= block.number){
            return;
        }

        uint256 mttoutput = poolData.currentMTTPerBlock * (block.number - poolData.lastOutputBlock);
        poolData.lastOutputBlock = block.number;

        poolData.currentOutputMTT += mttoutput;
        poolData.totalOutputMTT += mttoutput;

        emit OutputMTT(mttoutput, poolData);
    }

    function _startExped(
        uint256 inputGold,
        uint256 blockInterval,
        uint256 teamHashRate,
        ExpeditionPoolConf storage conf,
        ExpeditionTeamData storage teamData, 
        ExpeditionPoolData storage poolData
    ) internal {
        require(teamData.expedEndBlock < block.number, "Expedition: previous expedition not finish");

        require(blockInterval >= conf.minBlockInterval, "Expedition: block interval error");
        require(inputGold <= conf.goldPerHashrate*teamHashRate*blockInterval/conf.minBlockInterval, "Expedition: input gold error");

        // burn gold
        MTTGold(_MTTGoldAddr).burnFrom(_msgSender(), inputGold);

        teamData.inputGoldLeft += inputGold;
        teamData.expedLastFetchBlock = block.number;
        teamData.goldPerBlock = inputGold / blockInterval;
        teamData.expedEndBlock = block.number + blockInterval;

        poolData.totalInputGold += inputGold;
        poolData.currentInputGold += inputGold;

        emit StartExpedition(_msgSender(), teamData, poolData);
    }

    function _fetchExpedMTT(
        ExpeditionPoolConf storage conf,
        ExpeditionTeamData storage teamData, 
        ExpeditionPoolData storage poolData
    ) internal {
        require(teamData.inputGoldLeft > 0, "Expedition: insufficient input gold");
        require(teamData.expedLastFetchBlock < block.number, "Expedition: wait some blocks");

        uint256 goldCost = teamData.goldPerBlock * (block.number - teamData.expedLastFetchBlock);
        teamData.expedLastFetchBlock = block.number;

        if(goldCost > teamData.inputGoldLeft){
            goldCost = teamData.inputGoldLeft;
            teamData.inputGoldLeft = 0;
        }
        else {
            teamData.inputGoldLeft -= goldCost;
        }

        require(poolData.currentInputGold >= goldCost, "Expedition: gold underflow");

        uint256 value = poolData.currentOutputMTT * goldCost / poolData.currentInputGold;
        uint256 maxMTT = goldCost * conf.maxMTTPerGold / 10**8;
        if(value > maxMTT) {
            value = maxMTT;
        }

        MTTMinePool(_MTTMinePoolAddr).send(_msgSender(), value, "expedition");

        poolData.currentOutputMTT -= value;
        poolData.currentInputGold -= goldCost;

        emit FetchExpeditionMTT(_msgSender(), value, teamData, poolData);
    }

    function startHeroExped(uint16 portID, uint256 inputGold, uint256 blockInterval) external {
        PortHeroExpedPool storage phep = _heroExpeditions[portID];
        require(phep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        HeroExpeditionTeam storage team = phep.expedHeros[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");
    
        _startExped(inputGold, blockInterval, team.teamHashRate, phep.poolConf, team.teamData, phep.poolData);
    }
    function startShipExped(uint16 portID, uint256 inputGold, uint256 blockInterval) external {
        PortShipExpedPool storage psep = _shipExpeditions[portID];
        require(psep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        ShipExpeditionTeam storage team = psep.expedShips[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");
        
        _startExped(inputGold, blockInterval, team.teamHashRate, psep.poolConf, team.teamData, psep.poolData);
    }

    function fetchHeroExpedMTT(uint16 portID) external {
        PortHeroExpedPool storage phep = _heroExpeditions[portID];
        require(phep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        HeroExpeditionTeam storage team = phep.expedHeros[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");
    
        // output mtt
        _outputMTT(phep.poolData);

        _fetchExpedMTT(phep.poolConf, team.teamData, phep.poolData);
    }
    function fetchShipExpedMTT(uint16 portID) external {
        PortShipExpedPool storage psep = _shipExpeditions[portID];
        require(psep.poolConf.minMTTPerBlock > 0, "Expedition: port expedition config not exist");
        
        ShipExpeditionTeam storage team = psep.expedShips[_msgSender()];
        require(team.teamHashRate > 0, "Expedition: team not exist");
        
        // output mtt
        _outputMTT(psep.poolData);

        _fetchExpedMTT(psep.poolConf, team.teamData, psep.poolData);
    }

    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override pure returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return this.onERC721Received.selector;
    }
}

