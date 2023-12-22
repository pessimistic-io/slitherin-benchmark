// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./Counters.sol";
import "./MerkleProof.sol";
import "./IFoxifyAffiliationFull.sol";

contract FoxifyAffiliation is IFoxifyAffiliation, ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant TOTAL_SHARE = 1000;

    Counters.Counter private _tokensCount;
    string private _baseTokenURI;
    mapping(uint256 => EnumerableSet.AddressSet) private _teamUsers;
    mapping(address => EnumerableSet.UintSet) private _usersIDs;

    MergeLevelRates public mergeLevelRates;
    MergeLevelPermissions public mergeLevelPermissions;
    uint256 public teamsCount;
    Wave[] public waves;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(uint256 => NFTData) public data;
    mapping(address => uint256) public usersActiveID;
    mapping(address => uint256) public usersTeam;
    IFoxifyAffiliationFull public previousAffiliation;

    function currentWave() public view returns (uint256 id, Wave memory output) {
        if (waves.length > 0) {
            for (uint256 i = waves.length; i > 0; i--) {
                Wave memory wave = waves[i - 1];
                if (wave.start <= block.timestamp && wave.end >= block.timestamp) {
                    id = i - 1;
                    output = wave;
                    break;
                }
            }
        }
    }

    function dataList(uint256 offset, uint256 limit) external view returns (NFTData[] memory output) {
        uint256 tokensLength = _tokensCount.current();
        if (offset >= tokensLength) return new NFTData[](0);
        uint256 to = offset + limit;
        if (tokensLength < to) to = tokensLength;
        output = new NFTData[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = data[offset + i];
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _exists(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function teamUsers(uint256 team, uint256 index) external view returns (address) {
        return _teamUsers[team].at(index);
    }

    function teamUsersContains(uint256 team, address user) external view returns (bool) {
        return _teamUsers[team].contains(user);
    }

    function teamUsersLength(uint256 team) external view returns (uint256) {
        return _teamUsers[team].length();
    }

    function teamUsersList(
        uint256 team,
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory output) {
        uint256 usersLength = _teamUsers[team].length();
        if (offset >= usersLength) return new address[](0);
        uint256 to = offset + limit;
        if (usersLength < to) to = usersLength;
        output = new address[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _teamUsers[team].at(offset + i);
    }

    function tokensCount() external view returns (uint256) {
        return _tokensCount.current();
    }

    function usersIDs(address user, uint256 index) external view returns (uint256) {
        return _usersIDs[user].at(index);
    }

    function usersIDsContains(address user, uint256 id) external view returns (bool) {
        return _usersIDs[user].contains(id);
    }

    function usersIDsLength(address user) external view returns (uint256) {
        return _usersIDs[user].length();
    }

    function usersIDsList(address user, uint256 offset, uint256 limit) external view returns (uint256[] memory output) {
        uint256 idsLength = _usersIDs[user].length();
        if (offset >= idsLength) return new uint256[](0);
        uint256 to = offset + limit;
        if (idsLength < to) to = idsLength;
        output = new uint256[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = _usersIDs[user].at(offset + i);
    }

    function usersTeamList(address[] memory users) external view returns (uint256[] memory output) {
        output = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) output[i] = usersTeam[users[i]];
    }

    function wavesLength() external view returns (uint256) {
        return waves.length;
    }

    function wavesList(uint256 offset, uint256 limit) external view returns (Wave[] memory output) {
        uint256 wavesLength_ = waves.length;
        if (offset >= wavesLength_) return new Wave[](0);
        uint256 to = offset + limit;
        if (wavesLength_ < to) to = wavesLength_;
        output = new Wave[](to - offset);
        for (uint256 i = 0; i < output.length; i++) output[i] = waves[offset + i];
    }

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseTokenURI_,
        address previousAffiliation_
    ) ERC721(name_, symbol_) {
        require(previousAffiliation_ != address(0), "FoxifyAffiliation: Previous affiliation is zero address");
        previousAffiliation = IFoxifyAffiliationFull(previousAffiliation_);
        _baseTokenURI = baseTokenURI_;
        teamsCount = previousAffiliation.teamsCount();
        _tokensCount = Counters.Counter(previousAffiliation.tokensCount());
        _updateMergeLevelRates(previousAffiliation.mergeLevelRates());
        _updateMergeLevelPermissions(previousAffiliation.mergeLevelPermissions());
    }

    function batchTransferFrom(BatchParams[] memory params) external returns (bool) {
        for (uint256 i = 0; i < params.length; i++) {
            BatchParams memory param = params[i];
            transferFrom(param.from, param.to, param.id);
        }
        return true;
    }

    function merge(uint256[] memory ids, Level from) external nonReentrant returns (bool) {
        bool fromIsBronze = from == Level.BRONZE;
        require(fromIsBronze || from == Level.SILVER, "FoxifyAffiliation: Invalid from level");
        uint256 mergeRate = fromIsBronze ? mergeLevelRates.bronzeToSilver : mergeLevelRates.silverToGold;
        MergeLevelPermissions memory permissions = mergeLevelPermissions;
        Level to;
        if (fromIsBronze) {
            require(permissions.bronzeToSilver, "FoxifyAffiliation: BronzeToSilver permission denied");
            to = Level.SILVER;
        } else {
            require(permissions.silverToGold, "FoxifyAffiliation: SilverToGold permission denied");
            to = Level.GOLD;
        }
        require(mergeRate == ids.length, "FoxifyAffiliation: Invalid params length");
        uint256 tokenId = _safeMint(msg.sender);
        NFTData memory data_ = NFTData(to, keccak256(abi.encode(blockhash(block.number - 1))), block.timestamp);
        data[tokenId] = data_;
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            require(data[id].level == from, "FoxifyAffiliation: Level is not match");
            require(ownerOf(id) == msg.sender, "FoxifyAffiliation: Invalid id");
            _burn(id);
        }
        emit Merged(tokenId, ids, from, to);
        emit Minted(msg.sender, tokenId, data_);
        return true;
    }

    function migrate(uint256[] memory tokenIds) external returns (bool) {
        IERC721 previousAffiliation_ = IERC721(address(previousAffiliation));
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            previousAffiliation_.transferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, tokenId);
            data[tokenId] = previousAffiliation.data(tokenId);
            _safeMint(msg.sender, tokenId);
        }
        emit Migrated(msg.sender, tokenIds);
        _switchTeam(msg.sender, previousAffiliation.usersTeam(msg.sender));
        return true;
    }

    function mintRequest(bytes32[] calldata merkleProof, uint256 team) external returns (bool) {
        (uint256 waveIndex, Wave memory wave) = currentWave();
        require(block.timestamp >= wave.start && block.timestamp <= wave.end, "FoxifyAffiliation: All waves expired");
        require(!claimed[waveIndex][msg.sender], "FoxifyAffiliation: Already claimed");
        require(merkleProof.length > 0, "FoxifyAffiliation: Invalid proofs length");
        require(
            MerkleProof.verify(merkleProof, wave.root, keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))) ==
                true,
            "FoxifyAffiliation: Invalid proofs"
        );
        bytes32 _value = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender));
        uint256 randomValue = uint256(_value) % TOTAL_SHARE;
        Level level;
        if (randomValue < wave.distribution.bronze) {
            level = Level.BRONZE;
        } else if (randomValue < wave.distribution.bronze + wave.distribution.silver) {
            level = Level.SILVER;
        } else {
            level = Level.GOLD;
        }
        uint256 tokenId = _safeMint(msg.sender);
        NFTData memory data_ = NFTData(level, _value, block.timestamp);
        data[tokenId] = data_;
        emit Minted(msg.sender, tokenId, data_);
        _switchTeam(msg.sender, team);
        claimed[waveIndex][msg.sender] = true;
        return true;
    }

    function preMint(LevelsDistribution memory shares) external onlyOwner returns (bool) {
        require(waves.length == 0, "FoxifyAffiliation: Waves exists");
        uint256 tokensCount_ = shares.bronze + shares.silver + shares.gold;
        require(tokensCount_ > 0, "FoxifyAffiliation: Tokens count not positive");
        bytes32 pseudoRandom = keccak256(abi.encode(blockhash(block.number - 1)));
        for (uint256 i = 1; i <= tokensCount_; i++) {
            pseudoRandom = keccak256(abi.encode(pseudoRandom));
            Level level;
            if (i <= shares.bronze) {
                level = Level.BRONZE;
            } else if (i <= shares.bronze + shares.silver) {
                level = Level.SILVER;
            } else {
                level = Level.GOLD;
            }
            uint256 tokenId = _safeMint(msg.sender);
            NFTData memory data_ = NFTData(level, pseudoRandom, block.timestamp);
            data[tokenId] = data_;
            emit Minted(msg.sender, tokenId, data_);
        }
        return true;
    }

    function scheduleWave(Wave memory wave) external onlyOwner returns (bool) {
        require(wave.root != bytes32(0), "FoxifyAffiliation: Root is zero bytes");
        require(wave.start >= block.timestamp, "FoxifyAffiliation: Current lt start");
        require(wave.end > wave.start, "FoxifyAffiliation: End lte start");
        require(
            wave.distribution.bronze + wave.distribution.silver + wave.distribution.gold == TOTAL_SHARE,
            "FoxifyAffiliation: Distribution ne TOTAL_SHARE"
        );
        if (waves.length > 0) {
            Wave memory lastWave = waves[waves.length - 1];
            require(wave.start > lastWave.end, "FoxifyAffiliation: New wave start lt last wave end");
        }
        waves.push(wave);
        emit WaveScheduled(waves.length - 1, wave);
        return true;
    }

    function switchTeam(uint256 team) external returns (bool) {
        _switchTeam(msg.sender, team);
        return true;
    }

    function unscheduleWave(uint256 index) external onlyOwner returns (bool) {
        require(index < waves.length, "FoxifyAffiliation: Wave not exist");
        Wave memory targetWave = waves[index];
        require(targetWave.start > block.timestamp, "FoxifyAffiliation: Wave already started");
        for (uint256 i = index + 1; i < waves.length; i++) waves[i - 1] = waves[i];
        waves.pop();
        emit WaveUnscheduled(targetWave);
        return true;
    }

    function updateBaseURI(string memory uri) external onlyOwner returns (bool) {
        _baseTokenURI = uri;
        emit BaseURIUpdated(uri);
        return true;
    }

    function updateMergeLevelRates(MergeLevelRates memory rates) external onlyOwner returns (bool) {
        _updateMergeLevelRates(rates);
        return true;
    }

    function updateMergeLevelPermissions(MergeLevelPermissions memory permissions) external onlyOwner returns (bool) {
        _updateMergeLevelPermissions(permissions);
        return true;
    }

    function updateTeamsCount(uint256 count) external onlyOwner returns (bool) {
        require(count > teamsCount, "FoxifyAffiliation: Teams count lte current");
        teamsCount = count;
        emit TeamsCountUpdated(count);
        return true;
    }

    function updateUserActiveID(uint256 tokenId) external returns (bool) {
        if (tokenId > 0) require(ownerOf(tokenId) == msg.sender, "FoxifyAffiliation: Incorrect owner");
        usersActiveID[msg.sender] = tokenId;
        emit UserActiveIDUpdated(msg.sender, tokenId);
        return true;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _afterTokenTransfer(address from, address to, uint256 tokenId, uint256) internal override {
        _usersIDs[from].remove(tokenId);
        _usersIDs[to].add(tokenId);
        if (from != address(0) && balanceOf(from) == 0) {
            _teamUsers[usersTeam[from]].remove(from);
            delete usersTeam[from];
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (usersActiveID[from] == tokenId) {   
            usersActiveID[from] = 0;
            emit UserActiveIDUpdated(from, 0);
        }
    }

    function _safeMint(address to) private returns (uint256 tokenId) {
        _tokensCount.increment();
        tokenId = _tokensCount.current();
        _safeMint(to, tokenId);
    }

    function _switchTeam(address user, uint256 team) private {
        uint256 currentTeam = usersTeam[user];
        require(team <= teamsCount, "FoxifyAffiliation: Team not found");
        if (currentTeam != team) {
            _teamUsers[currentTeam].remove(user);
            _teamUsers[team].add(user);
            usersTeam[user] = team;
        }
        emit TeamSwitched(user, team);
    }

    function _updateMergeLevelRates(MergeLevelRates memory rates) private {
        require(rates.bronzeToSilver > 0 && rates.silverToGold > 0, "FoxifyAffiliation: Rate is not positive");
        mergeLevelRates = rates;
        emit MergeLevelRatesUpdated(rates);
    }

    function _updateMergeLevelPermissions(MergeLevelPermissions memory permissions) private {
        mergeLevelPermissions = permissions;
        emit MergeLevelPermissionsUpdated(permissions);
    }
}

