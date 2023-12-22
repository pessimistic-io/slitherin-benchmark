// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./Ownable.sol";

contract BondNFT is ERC721Enumerable, Ownable {
    
    uint256 constant private DAY = 1 days;
    uint256 constant private WEEKDAYS = 7;
    uint256 constant private COOLDOWN = 300;

    mapping(address => uint256) public epoch;
    uint256 private totalBonds;
    string public baseURI;
    address public manager;
    address[] public assets;

    mapping(address => bool) public allowedAsset;
    mapping(address => uint) private assetsIndex;
    mapping(uint256 => mapping(address => uint256)) private bondPaid;
    mapping(address => mapping(uint256 => uint256)) private accRewardsPerShare; // tigAsset => epoch => accRewardsPerShare
    mapping(uint256 => Bond) private _idToBond;
    mapping(address => uint) public totalShares;
    mapping(address => mapping(address => uint)) public userDebt; // user => tigAsset => amount

    struct Bond {
        uint256 id;
        address owner;
        address asset;
        bool expired;
        uint256 amount;
        uint256 mintEpoch;
        uint256 mintTime;
        uint256 expireEpoch;
        uint256 pending;
        uint256 shares;
        uint256 period;
    }

    event Distribution(address tigAsset, uint256 amount);
    event Lock(uint256 id, address tigAsset, uint256 amount, uint256 shares, uint256 period, address owner);
    event ExtendLock(uint256 id, uint256 amount, uint256 shares, uint256 period, address owner);
    event Release(uint256 id, address tigAsset, uint256 amount, address owner);
    event ClaimFees(uint256 id, address tigAsset, uint256 amount, address owner);
    event ClaimDebt(address tigAsset, uint256 amount, address owner);

    modifier onlyManager() {
        require(msg.sender == manager, "!manager");
        _;
    }

    constructor(
        string memory _setBaseURI,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        baseURI = _setBaseURI;
    }

    /**
     * @notice Create a bond
     * @dev Should only be called by a manager contract
     * @param _asset tigAsset token to lock
     * @param _amount tigAsset amount
     * @param _period time to lock for in days
     * @param _owner address to receive the bond
     * @return id ID of the minted bond
     */
    function createLock(
        address _asset,
        uint256 _amount,
        uint256 _period,
        address _owner
    ) external onlyManager() returns(uint256 id) {
        require(allowedAsset[_asset], "!Asset");
        require(_amount != 0, "Zero lock");
        require(epoch[_asset] == block.timestamp/DAY, "Bad epoch");
        unchecked {
            uint256 _shares = _amount * _period / 365;
            uint256 _expireEpoch = epoch[_asset] + _period;
            id = ++totalBonds;
            totalShares[_asset] += _shares;
            Bond memory _bond = Bond(
                id,             // id
                address(0),     // owner
                _asset,         // tigAsset token
                false,          // is expired boolean
                _amount,        // tigAsset amount
                epoch[_asset],  // mint epoch
                block.timestamp,// mint timestamp
                _expireEpoch,    // expire epoch
                0,              // pending
                _shares,         // linearly scaling share of rewards
                _period         // lock period
            );
            _idToBond[id] = _bond;
            _mint(_owner, _bond);
            emit Lock(id, _asset, _amount, _shares, _period, _owner);
        }
    }

    /** 
     * @notice Extend the lock period and/or amount of a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond
     * @param _asset tigAsset token address
     * @param _amount amount of tigAsset being added
     * @param _period days being added to the bond
     * @param _sender address extending the bond
     */
    function extendLock(
        uint256 _id,
        address _asset,
        uint256 _amount,
        uint256 _period,
        address _sender
    ) external onlyManager() {
        Bond memory bond = idToBond(_id);
        Bond storage _bond = _idToBond[_id];
        require(bond.owner == _sender, "!owner");
        require(!bond.expired, "Expired");
        require(bond.asset == _asset, "!BondAsset");
        require(bond.pending == 0);
        uint256 _currentEpoch = block.timestamp/DAY;
        require(epoch[bond.asset] == _currentEpoch, "Bad epoch");
        uint256 _pendingEpochs = bond.expireEpoch - _currentEpoch;
        uint256 _newBondPeriod = _pendingEpochs + _period;
        require(_newBondPeriod >= 7, "MIN PERIOD");
        require(bond.period+_period <= 365, "MAX PERIOD");

        unchecked {
            uint256 _shares = (bond.amount + _amount) * _newBondPeriod / 365;
            uint256 _expireEpoch = _currentEpoch + _newBondPeriod;
            totalShares[bond.asset] = totalShares[bond.asset]+_shares-bond.shares;
            _bond.shares = _shares;
            _bond.amount += _amount;
            _bond.expireEpoch = _expireEpoch;
            _bond.period = _newBondPeriod;
            _bond.mintTime = block.timestamp;
            _bond.mintEpoch = _currentEpoch;
            bondPaid[_id][bond.asset] = accRewardsPerShare[bond.asset][_currentEpoch] * _bond.shares / 1e18;

            emit ExtendLock(_id, _amount, _shares, _newBondPeriod, _sender);
        }
    }

    /**
     * @notice Release a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond
     * @param _releaser address initiating the release of the bond
     * @return amount amount of tigAsset returned
     * @return lockAmount amount of tigAsset locked in the bond
     * @return asset tigAsset token released
     * @return _owner bond owner
     */
    function release(
        uint256 _id,
        address _releaser
    ) external onlyManager() returns(uint256 amount, uint256 lockAmount, address asset, address _owner) {
        Bond memory bond = idToBond(_id);
        require(bond.expired, "!expire");
        if (_releaser != bond.owner) {
            unchecked {
                require(bond.expireEpoch + 7 < epoch[bond.asset], "Bond owner priority");
            }
        }
        amount = bond.amount;
        unchecked {
            totalShares[bond.asset] = totalShares[bond.asset] - bond.shares;
            uint256 _bondPaid = bondPaid[_id][bond.asset];

            uint256 _pendingDelta = (bond.shares * accRewardsPerShare[bond.asset][epoch[bond.asset]] / 1e18 - _bondPaid) - (bond.shares * accRewardsPerShare[bond.asset][bond.expireEpoch-1] / 1e18 - _bondPaid);

            uint256 _totalShares = totalShares[bond.asset];
            if (_totalShares > 0) {
                accRewardsPerShare[bond.asset][epoch[bond.asset]] += _pendingDelta*1e18/_totalShares;
            }
            (uint256 _claimAmount,) = claim(_id, bond.owner);
            amount = amount + _claimAmount;
        }
        asset = bond.asset;
        lockAmount = bond.amount;
        _owner = bond.owner;
        _burn(_id);
        emit Release(_id, asset, lockAmount, _owner);
    }
    /**
     * @notice Claim rewards from a bond
     * @dev Should only be called by a manager contract
     * @param _id ID of the bond to claim rewards from
     * @param _claimer address claiming rewards
     * @return amount amount of tigAsset claimed
     * @return tigAsset tigAsset token address
     */
    function claim(
        uint256 _id,
        address _claimer
    ) public onlyManager() returns(uint256 amount, address tigAsset) {
        Bond memory bond = idToBond(_id);
        require(_claimer == bond.owner, "!owner");
        amount = bond.pending;
        tigAsset = bond.asset;
        if (amount > 0) {
            unchecked {
                bondPaid[_id][bond.asset] += amount;
            }
            IERC20(tigAsset).transfer(manager, amount);
            emit ClaimFees(_id, tigAsset, amount, _claimer);            
        }
    }

    /**
     * @notice Claim user debt left from bond transfer
     * @dev Should only be called by a manager contract
     * @param _user user address
     * @param _tigAsset tigAsset token address
     * @return amount amount of tigAsset claimed
     */
    function claimDebt(
        address _user,
        address _tigAsset
    ) public onlyManager() returns(uint256 amount) {
        amount = userDebt[_user][_tigAsset];
        userDebt[_user][_tigAsset] = 0;
        IERC20(_tigAsset).transfer(manager, amount);
        emit ClaimDebt(_tigAsset, amount, _user);
    }

    /**
     * @notice Distribute rewards to bonds
     * @param _tigAsset tigAsset token address
     * @param _amount tigAsset amount
     */
    function distribute(
        address _tigAsset,
        uint256 _amount
    ) external {
        if (!allowedAsset[_tigAsset]) return;
        if (_amount > 0) {
            IERC20(_tigAsset).transferFrom(_msgSender(), address(this), _amount);
            emit Distribution(_tigAsset, _amount);
        }
        uint256 aEpoch;
        unchecked {
            aEpoch = block.timestamp / DAY;
            uint256 _epoch = epoch[_tigAsset];
            if (aEpoch > _epoch) {
                for (uint256 i=_epoch; i<aEpoch; i++) {
                    accRewardsPerShare[_tigAsset][i+1] = accRewardsPerShare[_tigAsset][i];
                }
                epoch[_tigAsset] = aEpoch;
            }
        }
        if (totalShares[_tigAsset] == 0) return;
        unchecked {
            accRewardsPerShare[_tigAsset][aEpoch] += _amount * 1e18 / totalShares[_tigAsset];
        }
    }

    /**
     * @notice Get all data for a bond
     * @param _id ID of the bond
     * @return bond Bond object
     */
    function idToBond(uint256 _id) public view returns (Bond memory bond) {
        bond = _idToBond[_id];
        bond.owner = ownerOf(_id);
        bond.expired = bond.expireEpoch <= epoch[bond.asset] ? true : false;
        unchecked {
            uint256 _accRewardsPerShare = accRewardsPerShare[bond.asset][bond.expired ? bond.expireEpoch-1 : epoch[bond.asset]];
            bond.pending = bond.shares * _accRewardsPerShare / 1e18 - bondPaid[_id][bond.asset];
        }
    }

    /*
     * @notice Get expired boolean for a bond
     * @param _id ID of the bond
     * @return bool true if bond is expired
     */
    function isExpired(uint256 _id) public view returns (bool) {
        Bond memory bond = _idToBond[_id];
        return bond.expireEpoch <= epoch[bond.asset] ? true : false;
    }

    /*
     * @notice Get pending rewards for a bond
     * @param _id ID of the bond
     * @return bool true if bond is expired
     */
    function pending(
        uint256 _id
    ) public view returns (uint256) {
        return idToBond(_id).pending;
    }

    function totalAssets() public view returns (uint256) {
        return assets.length;
    }

    /*
     * @notice Gets an array of all whitelisted token addresses
     * @return address array of addresses
     */
    function getAssets() public view returns (address[] memory) {
        return assets;
    }

    function _baseURI() internal override view returns (string memory) {
        return baseURI;
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal override {
        _transfer(from, to, tokenId);
    }

    function transferMany(address _to, uint256[] calldata _ids) external {
        unchecked {
            for (uint256 i=0; i<_ids.length; i++) {
                _transfer(_msgSender(), _to, _ids[i]);
            }
        }
    }

    function transferFromMany(address _from, address _to, uint256[] calldata _ids) external {
        unchecked {
            for (uint256 i=0; i<_ids.length; i++) {
                transferFrom(_from, _to, _ids[i]);
            }
        }
    }

    function approveMany(address _to, uint256[] calldata _ids) external {
        unchecked {
            for (uint256 i=0; i<_ids.length; i++) {
                approve(_to, _ids[i]);
            }
        }
    }

    function _mint(
        address to,
        Bond memory bond
    ) internal {
        unchecked {
            bondPaid[bond.id][bond.asset] = accRewardsPerShare[bond.asset][epoch[bond.asset]] * bond.shares / 1e18;
        }
        _mint(to, bond.id);
    }

    function _burn(
        uint256 _id
    ) internal override {
        delete _idToBond[_id];
        super._burn(_id);
    }

    function _transfer(
        address from,
        address to,
        uint256 _id
    ) internal override {
        Bond memory bond = idToBond(_id);
        require(bond.expireEpoch > block.timestamp/DAY, "Transfer after expiration");
        unchecked {
            require(block.timestamp > bond.mintTime + COOLDOWN, "Recent update");
            userDebt[from][bond.asset] += bond.pending;
            bondPaid[_id][bond.asset] += bond.pending;
        }
        super._transfer(from, to, _id);
    }

    function balanceIds(address _user) public view returns (uint256[] memory) {
        uint256[] memory _ids = new uint256[](balanceOf(_user));
        unchecked {
            for (uint256 i=0; i<_ids.length; i++) {
                _ids[i] = tokenOfOwnerByIndex(_user, i);
            }
        }
        return _ids;
    }

    function addAsset(address _asset) external onlyOwner {
        require(assets.length == 0 || assets[assetsIndex[_asset]] != _asset, "Already added");
        assetsIndex[_asset] = assets.length;
        assets.push(_asset);
        allowedAsset[_asset] = true;
        epoch[_asset] = block.timestamp/DAY;
    }

    function setAllowedAsset(address _asset, bool _bool) external onlyOwner {
        require(assets[assetsIndex[_asset]] == _asset, "Not added");
        allowedAsset[_asset] = _bool;
    }

    function setBaseURI(string calldata _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    function setManager(
        address _manager
    ) public onlyOwner() {
        manager = _manager;
    }
}
