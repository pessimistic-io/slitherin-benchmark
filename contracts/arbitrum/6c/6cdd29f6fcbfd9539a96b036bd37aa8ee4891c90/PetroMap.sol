// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721EnumerableUpgradeable.sol";
import "./ERC20Burnable.sol";
import "./CrudeOIL.sol";
import "./PetroAccessControl.sol";
import "./IPetroBank.sol";
import "./IStrategy.sol";
import "./IPetroRewardManager.sol";
import "./IRefinery.sol";

/// @title PetroMap
/// @author Petroleum Team
/// @notice Implemenation of the PetroMap NFT, the Plot and Map, manages the buyable items and the allocation of their bonuses.

contract PetroMap is PetroAccessControl, ERC721EnumerableUpgradeable{

  /// @notice Initializes the contract
  function initialize() public initializer {
    __ERC721_init("PetroleumPlot", "Plot");
    __PetroAccessControl_init();
  }

  /// @notice The struct that defines the different plots types
  struct PlotType{
    uint256 plotTypeID;

    uint256 price;
    uint256 plotBoost;
    uint256 plotStorage;
  }

  /// @notice The struct that defines the ObjectType
  struct ObjectType{
    uint256 objectTypeID;
    uint256 price;
    uint256 objectBoost;
    address strategy;

    uint256 max;
  }

  /// @notice The struct that defines the Object once it has been created and placed on the map.
  struct Object{
    uint256 objectType; // If = 0, then Object has not been instantited => case is Free
    uint256 StrategyID; // Address of the Strategy,
    uint256 x;
    uint256 y;
    uint256 rot;
  }

  /// @notice The struct that defines the Plot once it has been created.
  struct Plot{
    PlotType plotType;
    uint256 currentBoost; // 100 + BOOST
  }


  mapping(uint256 => PlotType) public plotTypeByID;
  mapping(uint256 => ObjectType) public ObjectTypeByID;

  mapping(uint256 => uint256) public MaxSupplyOfPlotType;
  mapping(uint256 => uint256) public CurrentSupplyOfPlotType;

  mapping(uint256 => Plot) public plotByID; // NFT ID to the Plot Object
  mapping(uint256 => mapping(uint256 => mapping(uint256 => Object))) public mapOfPlotID; //PLOT ID => X => Y => OBJECT

  mapping(uint256 => Object[]) public notMappedItemOfPlot;// Object linked to a plot but without XY coordinates
  mapping(uint256 => mapping(uint256 => uint256)) public amountOnPlot; //PLOT ID => ObjectID => Amount build on Plot,
  mapping(uint256 => bool) public isObjectLocked; // Lock the ability to buy an object
                                                                            
  // *** GIVEAWAY ***

  // *** Currency *** 
  mapping(address => bool) public currencyAuthorized;
  // *** Transfer ***
  bool public TransferPaused;

  
  // *** BaseEvent***
  event ItemBought(address Buyer, uint plotID, uint ObjectID, uint x, uint y);
  event ItemMoved(address Sender, uint256 plotID, uint x, uint y, uint newx, uint newy, uint rot);
  event PlotDeleted(address Owner, uint _ID);


  //***Remove at Index ***
  function getFreeIndex(uint256 _plotID,uint _lastx) public view returns(uint,uint)
  {
    for(uint i = _lastx; i < 10; i++){
      for(uint j = 0; j < 10; j++){
        if(mapOfPlotID[_plotID][i][j].objectType == 0)
        {
          return (i,j);
        }
      }
    }
    revert("No free cases in plot");
  }

  function _transfer(
        address from,
        address to,
        uint256 tokenId) internal override{
          require(!TransferPaused, "Transfer has been Paused");
          require(plotByID[tokenId].plotType.plotTypeID != 1, "Plot is not exchangeable");

          super._transfer(from,to,tokenId);
  }

  function mintPlot(uint256 _plotTypeID) public payable {
    require(msg.value == plotTypeByID[_plotTypeID].price, "Wrong Price");
    require(plotTypeByID[_plotTypeID].plotTypeID != 0, "Plot Type does not exist");
    require(MaxSupplyOfPlotType[_plotTypeID] > CurrentSupplyOfPlotType[_plotTypeID], "Max Supply of Plot Type reached");

    Plot memory plot = Plot(plotTypeByID[_plotTypeID],plotTypeByID[_plotTypeID].plotBoost);
    plotByID[totalSupply()] = plot;
    CurrentSupplyOfPlotType[_plotTypeID] += 1;

    _mint(msg.sender, super.totalSupply());
  }

  function buyItem(uint256 _plotID,uint _objectID, uint _x, uint _y, uint _rot, address _currency) public
  {
      require(_plotID <= super.totalSupply(), "Plot does not exist");
      require(_objectID != 0 && ObjectTypeByID[_objectID].objectTypeID != 0, "Invalid Object");
      require(currencyAuthorized[_currency], "Currency not Authorized");
      require(ownerOf(_plotID) == msg.sender, "Not Your Plot");
      require(mapOfPlotID[_plotID][_x][_y].objectType == 0, "Coord already in use");
      require(_x < 10 && _y < 10 && _rot < 5, "Wrond Coord");

      ObjectType memory objectType = ObjectTypeByID[_objectID];

      require(amountOnPlot[_plotID][_objectID] < objectType.max, "Max amount of Object reached for this plot");
      // require(isObjectLocked[_objectID] == false, "Object is locked");

      Object memory object = Object(_objectID,0,_x,_y,_rot);
      
      if(objectType.price != 0){
        ERC20(_currency).transferFrom(msg.sender,address(this), objectType.price);
      }

      if(_currency == CrudeOilAddress){
          instantRefinateCrudeOil(objectType.price);
      }

      if(objectType.strategy == RewardManagerAddress){
        //SPLIT PAYMENT
        sendToFeePumpBuy(objectType.price);
        
        // objectStrategyID represent the ID of the Node in the RewardManager or in any other strategy
        uint256 objectStrategyID  = IStrategy(objectType.strategy).createStrategy(_objectID, _plotID);
        object.StrategyID = objectStrategyID;
        mapOfPlotID[_plotID][_x][_y] = object;
      }
      else{

        if(objectType.price != 0){
          sendToFeeRegularItem(objectType.price);
        }

        if(objectType.objectBoost != 0){

          IPetroRewardManager(RewardManagerAddress).applyBoostToExistingNodeOfPlot(_plotID, objectType.objectBoost);
          plotByID[_plotID].currentBoost += objectType.objectBoost;

        }
        mapOfPlotID[_plotID][_x][_y] = object;
      }
      amountOnPlot[_plotID][_objectID] += 1;
     emit ItemBought(msg.sender,_plotID, _objectID, _x, _y);
  }

  function buySetOfItems(uint256 _plotID,uint[] memory _items, uint[] memory _x, uint[] memory _y, uint[] memory _rot,address _currency) public {
      for(uint i = 0; i < _items.length; i++)
      {
        buyItem(_plotID, _items[i], _x[i], _y[i], _rot[i],_currency);
      }
  }

  function quickBuy(uint256 _plotID, uint256 _item, uint256 _amount,address _currency) public
  {
    // require(ownerOf(_plotID) == msg.sender, "Not Your Plot");
    (uint lastx) = 0;
    for(uint i = 0; i < _amount; i++)
    {
      (uint256 a,uint256 b) = getFreeIndex(_plotID,lastx);
      lastx = a;
      buyItem(_plotID,_item,a,b,1,_currency);
    }
  }

  function moveItem(uint256 _plotID, uint _x, uint _y, uint _newx, uint _newy, uint _rot) public
  {
    require(ownerOf(_plotID) == msg.sender, "Not Your Plot");
    require(_x < 10 && _y < 10 && _newx < 10 && _newy < 10, "Wrond Coord");
    require(mapOfPlotID[_plotID][_x][_y].objectType != 0, "No Item at Cord");
    require(mapOfPlotID[_plotID][_newx][_newy].objectType == 0, "Not Empty");
    
    if(_x != _newx || _y != _newy){
      mapOfPlotID[_plotID][_newx][_newy] = mapOfPlotID[_plotID][_x][_y];
      delete(mapOfPlotID[_plotID][_x][_y]);
    }
    emit ItemMoved(msg.sender, _plotID, _x, _y, _newx, _newy, _rot);
  }

  function setObjectPrice(uint _objectID, uint _price) public onlyRole(GAME_MANAGER)
  {
    ObjectTypeByID[_objectID].price = _price;
  }

  function instantRefinateCrudeOil(uint256 _amount) internal {
        ERC20(CrudeOilAddress).approve(RefineryAddress, _amount);
        IRefinery(RefineryAddress).instantRefinate(_amount);
  }

  function sendToFeePumpBuy(uint256 _amount) internal{

      uint256 BURN_AMOUNT = _amount * 60 / 100 ;

        uint256 LMS_AMOUNT_OIL = _amount * 10 / 100 ;
        uint256 LMS_AMOUNT_DAI = _amount * 10 / 100 ;
        uint256 TREASURY_AMOUNT = _amount * 10 / 100 ;
        uint256 DEV_AMOUNT = _amount * 10 / 100 ;

        ERC20Burnable(OilAddress).burn(BURN_AMOUNT);

        /// ******** BEFORE PRESALE ********
        ERC20(OilAddress).transfer(PetroLiquidityManagerAddress, LMS_AMOUNT_DAI + LMS_AMOUNT_OIL);
        ERC20(OilAddress).transfer(TreasuryAddress, TREASURY_AMOUNT);
        ERC20(OilAddress).transfer(DevPay, DEV_AMOUNT);

        /// ******** AFTER PRESALE ********

        // ERC20(OilAddress).transfer(PetroLiquidityManagerAddress, LMS_AMOUNT_OIL);

        // uint256 SellAmount = LMS_AMOUNT_DAI + TREASURY_AMOUNT + DEV_AMOUNT;

        // ERC20(OilAddress).approve(PetroBankAddress, SellAmount);

        // uint256 BeforeAmount = IERC20(DAI).balanceOf(address(this));
        // IPetroBank(PetroBankAddress).sell(SellAmount);
        // uint256 RealAmount = IERC20(DAI).balanceOf(address(this)) - BeforeAmount;

        // // resplit in case of slippage
        // ERC20(DAI).transfer(PetroLiquidityManagerAddress, RealAmount/3 );
        // ERC20(DAI).transfer(TreasuryAddress, RealAmount/3 );
        // ERC20(DAI).transfer(DevWallet, RealAmount/3 );
    }

  function sendToFeeRegularItem(uint256 _amount) internal{

      ERC20(OilAddress).transfer(DevPay, _amount / 2);
      ERC20(OilAddress).transfer(TreasuryAddress, _amount / 2);
      // ERC20(OilAddress).approve(PetroBankAddress, _amount);

      // uint256 BeforeAmount = IERC20(DAI).balanceOf(address(this));

      // IPetroBank(PetroBankAddress).sell(_amount);

      // uint256 RealAmount = IERC20(DAI).balanceOf(address(this)) - BeforeAmount;


      // ERC20(DAI).transfer(PetroLiquidityManagerAddress, RealAmount/2);
      // ERC20(DAI).transfer(DevWallet, RealAmount/2);
  }

  function createNode(uint _objectID, uint _price, uint _durability, uint _reward, uint _storage, uint _clogReduction,uint256 _levelUpPrice,uint256 _repairPrice,uint256 _maxOnPlot) public onlyRole(GAME_MANAGER) {

    ObjectType memory newType = ObjectType(_objectID,_price,0,RewardManagerAddress,_maxOnPlot);
    ObjectTypeByID[_objectID] = newType;

    IPetroRewardManager(RewardManagerAddress).createNodeType(_objectID,_durability,_storage,_reward,_clogReduction,_levelUpPrice,_repairPrice,2 hours,2,0);
  }

  function createObject(uint256 _objectID,uint256 _price, uint256 _boost,uint256 _maxItem) public onlyRole(GAME_MANAGER){

    ObjectType memory newType = ObjectType(_objectID,_price * 1 ether,_boost,address(0), _maxItem);
    ObjectTypeByID[_objectID] = newType;
  }

  function createPlotType(uint256 _plotTypeID, uint256 _price, uint256 _boost,uint256 _storage,uint256 _maxPlotSupply) public onlyRole(GAME_MANAGER) {
    PlotType memory plotType = PlotType(_plotTypeID,_price,_boost,_storage);
    plotTypeByID[_plotTypeID] = plotType;
    MaxSupplyOfPlotType[_plotTypeID] = _maxPlotSupply;
  }
  
  function boostPlotProduction(uint256 _plotID, uint256 _amount) public onlyRole(GAME_MANAGER) {
    plotByID[_plotID].currentBoost += _amount;
  }
  //GETTERS

  function returnMap(uint _plotID) public view returns(Object[10][10] memory){
    Object[10][10] memory _map;
    for(uint i = 0; i < 10; i++){
      for(uint j = 0; j < 10; j++)
      {
        _map[i][j] = mapOfPlotID[_plotID][i][j];
      }
    }
    return _map;
  }

  function getNotMappedItemOfPlot(uint256 _plotID) public view returns (Object[] memory){
    return notMappedItemOfPlot[_plotID];
  }
  function getPlotByID(uint256 _plotID) public view returns (Plot memory){
    return plotByID[_plotID];
  }
  function getPlotIDOfUser(address _user) public view returns (uint256[] memory){
    uint256 len = balanceOf(_user);
    uint256[] memory plotOfUser = new uint[](len);
    for(uint i = 0; i < balanceOf(_user) ; i++){
      plotOfUser[i] = (super.tokenOfOwnerByIndex(_user,i));
    }
    return plotOfUser;
  }
  function getPriceOfObject(uint256 _objectID) public view returns (uint256){
    return ObjectTypeByID[_objectID].price;
  }

  function getNodeIDAtCoord(uint256 _plotID, uint256 _x, uint256 _y) public view returns (uint256){
    return mapOfPlotID[_plotID][_x][_y].StrategyID;
  }

  function getObjectTypeOfListOfID(uint256[] memory _objectIDs) public view returns(ObjectType[] memory)
  {
    uint256 len = _objectIDs.length;
    ObjectType[] memory res = new ObjectType[](len);
    for(uint256 i = 0; i < len; i++)
    {
      res[i] = ObjectTypeByID[_objectIDs[i]];
    }
    return res;
  }

  function changeStrategyOfObject(uint _id, address _newStrategy) public onlyRole(GAME_MANAGER){
    ObjectTypeByID[_id].strategy = _newStrategy;
  }
  function changeTrading(bool _tradingStatus) public onlyRole(GAME_MANAGER){
    TransferPaused = _tradingStatus;
  }
  function changePriceOfObject(uint _id, uint _newPrice) public onlyRole(GAME_MANAGER){
    ObjectTypeByID[_id].price = _newPrice;
  }
  function setCurrencyAuthorized(address _currency,bool _value) public onlyRole(GAME_MANAGER){
    currencyAuthorized[_currency] = _value;
  }

  function changeMax(uint256 _objectID, uint256 _value) public onlyRole(GAME_MANAGER){
    ObjectTypeByID[_objectID].max = _value;
  }

  // GiveAway functions
  function giveFreePlot(address _toGive, uint256 _plotTypeID) public onlyRole(GAME_MANAGER) {
    require(plotTypeByID[_plotTypeID].plotTypeID != 0, "Plot Type does not exist");
    require(MaxSupplyOfPlotType[_plotTypeID] > CurrentSupplyOfPlotType[_plotTypeID], "Max Supply of Plot Type reached");


    Plot memory plot = Plot(plotTypeByID[_plotTypeID],plotTypeByID[_plotTypeID].plotBoost);
    plotByID[totalSupply()] = plot;
    CurrentSupplyOfPlotType[_plotTypeID] += 1;

    _mint(_toGive, super.totalSupply());
  }
  function changeMaxSupplyOfPlotType(uint256 _plotTypeID, uint256 _newMaxSupply) public onlyRole(GAME_MANAGER) {
    MaxSupplyOfPlotType[_plotTypeID] = _newMaxSupply;
  }

  function _baseURI() internal pure override returns (string memory) {
    return "http://api.petroleum.land/plotMetadata/";
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721EnumerableUpgradeable, AccessControlUpgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  uint256[45] private __gap;

}

