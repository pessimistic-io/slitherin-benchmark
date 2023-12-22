// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFoxifyAffiliation {
    enum Level {
        UNKNOWN,
        BRONZE,
        SILVER,
        GOLD
    }

    struct BatchParams {
        address from;
        address to;
        uint256 id;
    }

    struct LevelsDistribution {
        uint256 bronze;
        uint256 silver;
        uint256 gold;
    }

    struct MergeLevelRates {
        uint256 bronzeToSilver;
        uint256 silverToGold;
    }

    struct MergeLevelPermissions {
        bool bronzeToSilver;
        bool silverToGold;
    }

    struct NFTData {
        Level level;
        bytes32 randomValue;
        uint256 timestamp;
    }

    struct Wave {
        bytes32 root;
        uint256 start;
        uint256 end;
        LevelsDistribution distribution;
    }

    event BaseURIUpdated(string uri);
    event Merged(uint256 indexed tokenId, uint256[] ids, Level from, Level to);
    event MergeLevelRatesUpdated(MergeLevelRates rates);
    event Migrated(address indexed migrator, uint256[] tokenIds);
    event MergeLevelPermissionsUpdated(MergeLevelPermissions permissions);
    event Minted(address indexed recipient, uint256 tokenId, NFTData data);
    event TeamsCountUpdated(uint256 count);
    event TeamSwitched(address indexed user, uint256 teamId);
    event UserActiveIDUpdated(address indexed user, uint256 indexed tokenId);
    event WaveScheduled(uint256 index, Wave wave);
    event WaveUnscheduled(Wave wave);

    function TOTAL_SHARE() external view returns (uint256);

    function teamsCount() external view returns (uint256);

    function claimed(uint256, address) external view returns (bool);

    function usersActiveID(address) external view returns (uint256);

    function usersTeam(address) external view returns (uint256);

    function currentWave() external view returns (uint256 id, Wave memory output);

    function dataList(uint256 offset, uint256 limit) external view returns (NFTData[] memory output);

    function exists(uint256 tokenId) external view returns (bool);

    function teamUsers(uint256 team, uint256 index) external view returns (address);

    function teamUsersContains(uint256 team, address user) external view returns (bool);

    function teamUsersLength(uint256 team) external view returns (uint256);

    function teamUsersList(uint256 offset, uint256 limit, uint256 team) external view returns (address[] memory output);

    function tokensCount() external view returns (uint256);

    function usersIDs(address user, uint256 index) external view returns (uint256);

    function usersIDsContains(address user, uint256 id) external view returns (bool);

    function usersIDsLength(address user) external view returns (uint256);

    function usersIDsList(address user, uint256 offset, uint256 limit) external view returns (uint256[] memory output);

    function usersTeamList(address[] memory users) external view returns (uint256[] memory output);

    function wavesList(uint256 offset, uint256 limit) external view returns (Wave[] memory output);

    function batchTransferFrom(BatchParams[] memory params) external returns (bool);

    function merge(uint256[] memory ids, Level from) external returns (bool);

    function mintRequest(bytes32[] calldata merkleProof, uint256 team) external returns (bool);

    function preMint(LevelsDistribution memory shares) external returns (bool);

    function scheduleWave(Wave memory wave) external returns (bool);

    function switchTeam(uint256 team) external returns (bool);

    function unscheduleWave(uint256 index) external returns (bool);

    function updateBaseURI(string memory uri) external returns (bool);

    function updateMergeLevelRates(MergeLevelRates memory rates) external returns (bool);

    function updateMergeLevelPermissions(MergeLevelPermissions memory permissions) external returns (bool);

    function updateTeamsCount(uint256 count) external returns (bool);

    function updateUserActiveID(uint256 tokenId) external returns (bool);
}

