// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./ERC721Holder.sol";
import "./IERC721.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC721Enumerable.sol";
import "./ReentrancyGuard.sol";

interface NFTLuggageInfo {
    function viewInfoLuggage(uint256 _tokenId) external view returns(uint8, uint8);
}

contract StakingTokenEarnLug is Pausable, ERC721Holder, Ownable, ReentrancyGuard {

    NFTLuggageInfo public infoLug;

    ERC20 token;
    address nft;

    struct packageInfo{
        uint256 totalAmoutNft;
        uint256 currentAmountNft;
        uint256 valueA;
        uint256 valueB;
    }
    uint256 decimal = 10**18;

    struct userStakingInfo {
        bool isActive;
        uint256 amountStakedToken;
        uint256 startTime;
        uint256 endTime;
        uint256 fullLockedDays;
        uint256 tokenId;
    }

    struct tokenIdPackageInfo{
        bool    isValue;
        uint256[] tokenidList;
    }

    mapping(uint8 => packageInfo) public packageInfoList;
    mapping(uint256 => mapping(bytes32 => userStakingInfo)) public userStakingInfoList;
    mapping(uint256 => tokenIdPackageInfo) public tokenIdPackageInfoList;

    uint256 public amountStakedToken;
    uint256 public amountFarmingNft;

    constructor(ERC20 _token, address _nft)
    {
        infoLug = NFTLuggageInfo(_nft);
        token = _token;
        nft = _nft;

        setPackageInfo([11,12,13,14], 350, 5, 500);
        setPackageInfo([21,22,23,24], 100, 6, 600);
        setPackageInfo([31,32,33,34], 45, 9, 900);
        setPackageInfo([41,42,43,44], 5, 10, 1000);
        token.approve(address(this), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    function setTokenidPackage(uint8 _idPackage, uint256[] memory _tokenidList) external onlyOwner
    {
        tokenIdPackageInfo storage info = tokenIdPackageInfoList[_idPackage];

        for(uint256 i  = 0; i < _tokenidList.length; i++)
        {
            info.tokenidList.push(_tokenidList[i]);
        }
        info.isValue = true;
    }

    function setPackageInfo(uint8[4] memory _idArr,uint256 _maxAmoutNft,uint256 _valueA, uint256 _valueB) public onlyOwner
    {
        require(_valueA != 0 , "Value A Is Not Available");
        require(_valueB != 0 , "Value B Is Not Available");
        for(uint256 i  = 0; i < _idArr.length; i++)
        {
            packageInfo memory info = packageInfo(_maxAmoutNft, 0,_valueA, _valueB);
            packageInfoList[_idArr[i]] = info;
        }
    }

    function stake(string memory _idTurn, uint256 _ndays, uint8 _quality, uint8 _type) external
    {
        uint8 _packageId = getPackageId(_quality, _type);
        uint256 _tokenId = getTokenidPackage(_packageId);

        bool _isNft = checkNftInfo(_tokenId, _quality, _type);
        require(_isNft == true, "TokenID Is Not Available");

        packageInfo storage packInfo = packageInfoList[_packageId];

        require(packInfo.totalAmoutNft > 0, "NFT Is Not Available");

        bytes32 _value = keccak256(abi.encodePacked(msg.sender, _idTurn));
        require(userStakingInfoList[_packageId][_value].isActive == false, "User Already Staked With This Staking ID");

        packageInfo memory info = packageInfoList[_packageId];

        uint256 _amountToken = calculateToken(info.valueA, info.valueB, _ndays);

        require( _ndays > 0, "Number of day have to be larger than 0");
        require( _ndays <= 90,"Number of day have to be smaller or equal than 90");

        require (token.balanceOf(msg.sender) >= _amountToken, "User Does Not Have Enough");
        token.transferFrom(msg.sender, address(this), _amountToken);
        amountStakedToken = amountStakedToken + _amountToken;
        amountFarmingNft+=1;
        packInfo.totalAmoutNft -=1;
        packInfo.currentAmountNft +=1;
        addUserStaking(msg.sender, _idTurn, _amountToken, _ndays, _packageId, _tokenId);
    }

    function getTokenidPackage(uint8 _idPackage) internal returns(uint256 _tokenId)
    {
        tokenIdPackageInfo storage info = tokenIdPackageInfoList[_idPackage];
        require(info.isValue,"ID Package Is Not Available");

        _tokenId = info.tokenidList[0];
        for(uint i = 0; i < info.tokenidList.length-1; i++){
            info.tokenidList[i] = info.tokenidList[i+1];
        }
        info.tokenidList.pop();
        return _tokenId;
    }

    function addUserStaking(address _addressUser,
        string memory _idTurn,
        uint256 _amountToken,
        uint256 _ndays,
        uint256 _packageId,
        uint256 _tokenId)
    internal
    {
        bytes32 _value = keccak256(abi.encodePacked(_addressUser, _idTurn));
        uint256 _secondsDays = convertDaysToSeconds(_ndays);
        uint256 _endTime = block.timestamp + _secondsDays;
        userStakingInfo memory info = userStakingInfo(
            true,
            _amountToken,
            block.timestamp,
            _endTime,
            _ndays,
            _tokenId
        );
        userStakingInfoList[_packageId][_value] = info;
    }

    function checkNftInfo(uint256 _tokenId, uint256 _quality, uint256 _type) internal view returns(bool _result)
    {
        uint256 quality;
        uint256 types;
        (quality, types) = infoLug.viewInfoLuggage(_tokenId);
        if (quality == _quality && types == _type)
        {_result = true;}
        else
        {_result = false;}
        return _result;
    }

    function viewNftInfo(uint256 _tokenId) public view returns(uint8,uint8)
    {
        uint8 quality;
        uint8 types;
        (quality, types) = infoLug.viewInfoLuggage(_tokenId);
        return(quality, types);
    }

    function getPackageId(uint8 _quality, uint8 _type) internal pure returns(uint8 _result)
    {
        return (_quality * 10 + _type );
    }

    function unStake(string memory _idTurn, uint8 _quality, uint8 _type) public
    {
        uint256 _packageId = getPackageId(_quality, _type);
        bytes32 _value = keccak256(abi.encodePacked(msg.sender, _idTurn));
        userStakingInfo storage userInfo = userStakingInfoList[_packageId][_value];
        require(userInfo.isActive == true, "UnStaking: Not allowed unstake two times");
        require(userInfo.endTime <= block.timestamp, "This Staking Is Not Ready");

        uint256 _claimableTokenToken = userInfo.amountStakedToken;
        uint256 _tokenId = userInfo.tokenId;

        require(_claimableTokenToken > 0, "Unstaking: Nothing to claim");
        amountStakedToken = amountStakedToken - _claimableTokenToken;
        delete userStakingInfoList[_packageId][_value];

        token.transfer(msg.sender,_claimableTokenToken);
        IERC721(nft).safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    function calculateToken(uint256 _valueA, uint256 _valueB, uint256 _ndays) internal view returns(uint256)
    {
        require( _ndays > 0, "Number of day have to be larger than 0");
        require( _ndays <= 90,"Number of day have to be smaller or equal than 90");
        // y = -ax + b => b - ax
        uint256 y  =  (_valueB - (_valueA * _ndays)) * 1000;
        return (y * decimal);
    }

    function getAmountToken(uint8 _packageId, uint256 _ndays) public view returns (uint256)
    {
        packageInfo memory info = packageInfoList[_packageId];
        uint256 _results = calculateToken(info.valueA, info.valueB, _ndays);
        return _results;
    }

    function convertDaysToSeconds(uint256 _ndays) internal pure returns(uint256)
    {
        return _ndays* 24 hours;
    }

    function viewStakingUser(address _addressUser,string memory _idTurn, uint8 _quality, uint8 _type) public view returns(bool,uint256,uint256,uint256,uint256,uint256)
    {
        uint8 _packageId = getPackageId(_quality, _type);
        bytes32 _value = keccak256(abi.encodePacked(_addressUser, _idTurn));
        userStakingInfo memory info = userStakingInfoList[_packageId][_value];
        return(
        info.isActive,
        info.amountStakedToken,
        info.startTime,
        info.endTime,
        info.fullLockedDays,
        info.tokenId
        );
    }

    function viewTokenIdPackageInfoList(uint256 _idPackage) external view returns(uint256[] memory )
    {
        return(tokenIdPackageInfoList[_idPackage].tokenidList);
    }

    function UserStaking(address _addressUser,string memory _idTurn, uint8 _quality,uint8 _type, bool _isActive,
        uint256 _amountStakedToken, uint256 _startTime, uint256 _endTime, uint8 _fullLockedDays, uint256 _tokenId )
    external onlyOwner
    {
        uint8 _packageId = getPackageId(_quality, _type);
        bytes32 _value = keccak256(abi.encodePacked(_addressUser, _idTurn));
        userStakingInfo storage info = userStakingInfoList[_packageId][_value];
        info.isActive = _isActive;
        info.amountStakedToken = _amountStakedToken;
        info.startTime = _startTime;
        info.endTime = _endTime;
        info.fullLockedDays = _fullLockedDays;
        info.tokenId = _tokenId;
    }

    // amount BNB
    function withdrawNative(uint256 _amount) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require( address(this).balance >= _amount ,"balanceOfNative:  is not enough");
        payable(msg.sender).transfer(_amount);
    }

    function withdrawToken(IERC20 _token, uint256 _amount) public onlyOwner {
        require(_amount > 0 , "_amount must be greater than 0");
        require(_token.balanceOf(address(this)) >= _amount , "balanceOfToken:  is not enough");
        _token.transfer(msg.sender, _amount);
    }

    // all BNB
    function withdrawNativeAll() public onlyOwner {
        require(address(this).balance > 0 ,"balanceOfNative:  is equal 0");
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawTokenAll(IERC20 _token) public onlyOwner {
        require(_token.balanceOf(address(this)) > 0 , "balanceOfToken:  is equal 0");
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    function withdrawNFT(uint256 _tokenId, address _beneficiary, address erc721) public onlyOwner{
        IERC721(erc721).safeTransferFrom(address(this), _beneficiary, _tokenId);
    }

    function withdrawAllNFT(address _beneficiary, address erc721) public onlyOwner{
        uint256 _amountBox = IERC721Enumerable(erc721).balanceOf(address(this));
        for (uint256 i = 0; i < _amountBox; i++) {
            uint256 _tokenId = IERC721Enumerable(erc721).tokenOfOwnerByIndex(address(this), 0);
            IERC721(erc721).safeTransferFrom(address(this), _beneficiary, _tokenId);
        }
    }

    event Received(address, uint);
    receive () external payable {
        emit Received(msg.sender, msg.value);
    }
}

