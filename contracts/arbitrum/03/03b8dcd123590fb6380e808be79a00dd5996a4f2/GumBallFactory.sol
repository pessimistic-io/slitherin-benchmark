// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Ownable.sol";

interface IGBTFactory {
    function createGBT(
        string memory _name,
        string memory _symbol,
        address _baseToken,
        uint256 _initialVirtualBASE,
        uint256 _supplyGBT,
        address _artist,
        address _factory,
        uint256 _delay,
        uint256 _fee
    ) external returns (address);
}

interface IGNFTFactory {
    function createGNFT(
        string memory _name,
        string memory _symbol,
        string[] memory _URIs,
        address _GBT,
        uint256 _bFee
    ) external returns (address);
}

interface IXGBTFactory {
    function createXGBT(
        address _owner,
        address _stakingToken,
        address _stakingNFT
    ) external returns (address);
}

interface IGBT {
    function setXGBT(address _XGBT) external;
    function updateAllowlist(address[] memory accounts, uint256 amount) external;
}

interface IXGBT {
    function addReward(address _rewardsToken) external;
}

contract GumBallFactory is Ownable {
    address public GBTFactory;
    address public GNFTFactory;
    address public XGBTFactory;
    address public treasury;
    address public zapper;

    struct GumBall {
        address GBT;
        address GNFT;
        address XGBT;
        bool allowed;
    }

    GumBall[] public gumballs;
    mapping(address => uint256) public indexes; // GBT => index
    mapping(address => bool) public allowlist;

    event TreasurySet(address _treasury);
    event GumBallDeployed(address indexed gbt, address indexed gnft, address indexed xgbt);
    event GBTFactorySet(address gbtFactory);
    event GNFTFactorySet(address gnftFactory);
    event XGBTFactorySet(address xgbtFactory);
    event AllowExisting(uint256 index, bool _bool);
    event FactoryAllowlistUpdate(address _factory, bool flag);
    event GumBallAdded(address indexed _gbt, address indexed _gnft, address indexed _xgbt);
    event ZapperSet(address _zapper);

    constructor(address _GBTFactory, address _GNFTFactory, address _XGBTFactory, address _treasury) {
        GBTFactory = _GBTFactory;
        GNFTFactory = _GNFTFactory;
        XGBTFactory = _XGBTFactory;
        treasury = _treasury;
    }

    function deployInfo(uint256 id) external view returns (address token, address nft, address gumbar, bool _allowed) {	
        return (gumballs[id].GBT, gumballs[id].GNFT, gumballs[id].XGBT, gumballs[id].allowed);
    }

    function totalDeployed() external view returns (uint256 length) {	
        return gumballs.length;	
  }

    function getTreasury() external view returns (address) {
        return treasury;
    }

    function getZapper() external view returns (address) {
        return zapper;
    }

    function deployGumBall(
        string calldata _name,
        string calldata _symbol,
        string[] calldata _URIs,
        uint256 _supplyBASE,
        uint256 _supplyGBT,
        address _base,
        address _artist,
        uint256 _delay,
        uint256[] memory _fees
    ) external {
        require(bytes(_name).length != 0 && bytes(_symbol).length != 0 && bytes(_URIs[0]).length != 0 && bytes(_URIs[1]).length != 0, "Incomplete name, symbol or URI");
        require(_URIs.length == 2 && _supplyGBT >= 1 && _supplyBASE >=1, "Invalid URI length, supply or virtual base");
        require(_base != address(0) && _artist != address(0), "Base token or artist cannot be zero address");
        require(_delay <= 1209600, "14 day max");
        string memory nameGNFT = string(abi.encodePacked(_name));
        string memory symbolGNFT = string(abi.encodePacked(_symbol));

        address gbt = IGBTFactory(GBTFactory).createGBT(nameGNFT, symbolGNFT, _base, _supplyBASE, _supplyGBT, _artist, address(this), _delay, _fees[0]);
        address gnft = IGNFTFactory(GNFTFactory).createGNFT(nameGNFT, symbolGNFT, _URIs, gbt, _fees[1]);
        address xgbt = IXGBTFactory(XGBTFactory).createXGBT(address(this), gbt, gnft);
        
        IGBT(gbt).setXGBT(xgbt);
        IXGBT(xgbt).addReward(gbt);
        IXGBT(xgbt).addReward(_base);

        bool allow;
        if (allowlist[msg.sender]) {
            allow = true;
        } else {
            allow = false;
        }

        uint256 index = gumballs.length;
        indexes[gbt] = index;

        GumBall memory gumball = GumBall(gbt, gnft, xgbt, allow);
        gumballs.push(gumball);

        emit GumBallDeployed(gbt, gnft, xgbt);
    }

    function addExistingGumBall(address _gbt, address _xgbt, address _gnft) external onlyOwner {
        uint256 index = gumballs.length;
        indexes[_gbt] = index;
        
        GumBall memory gumball = GumBall(_gbt, _gnft, _xgbt, true);
        gumballs.push(gumball);

        emit GumBallDeployed(_gbt, _gnft, _xgbt);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function setGBTFactory(address _GBTFactory) external onlyOwner {
        GBTFactory = _GBTFactory;
        emit GBTFactorySet(_GBTFactory);
    }

    function setGNFTFactory(address _GNFTFactory) external onlyOwner {
        GNFTFactory = _GNFTFactory;
        emit GNFTFactorySet(_GNFTFactory);
    }

    function setXGBTFactory(address _XGBTFactory) external onlyOwner {
        XGBTFactory = _XGBTFactory;
        emit XGBTFactorySet(_XGBTFactory);
    }

    function setZapper(address _zapper) external onlyOwner {
        zapper = _zapper;
        emit ZapperSet(_zapper);
    }

    function updateFactoryAllowlist(address _addr, bool _bool) external onlyOwner {
        allowlist[_addr] = _bool;
        emit FactoryAllowlistUpdate(_addr, _bool);
    }

    function allowExisting(uint256 _index, bool _bool) external onlyOwner {
        gumballs[_index].allowed = _bool;
        emit AllowExisting(_index, _bool);
    }

    /////////////////////
    //////// GBT ////////
    /////////////////////

    function updateGumBallAllowlist(address _tokenAddr, address[] calldata _accounts, uint256 _amount) external onlyOwner {
        IGBT(_tokenAddr).updateAllowlist(_accounts, _amount);
    }

    ////////////////////
    /////// XGBT ///////
    ////////////////////

    function addReward(address _gumbarAddr, address _rewardsToken) external onlyOwner {
        IXGBT(_gumbarAddr).addReward(_rewardsToken);
    }

}
