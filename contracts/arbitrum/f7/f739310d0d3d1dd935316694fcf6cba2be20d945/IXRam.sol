// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

interface IXRam {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event CancelVesting(
        address indexed user,
        uint256 indexed vestId,
        uint256 amount
    );
    event ExitVesting(
        address indexed user,
        uint256 indexed vestId,
        uint256 amount
    );
    event Initialized(uint8 version);
    event InstantExit(address indexed user, uint256);
    event NewExitRatios(uint256 exitRatio, uint256 veExitRatio);
    event NewVest(
        address indexed user,
        uint256 indexed vestId,
        uint256 indexed amount
    );
    event NewVestingTimes(uint256 min, uint256 max, uint256 veMaxVest);
    event RamConverted(address indexed user, uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event WhitelistStatus(address indexed candidate, bool status);
    event XRamRedeemed(address indexed user, uint256);

    function MAXTIME() external view returns (uint256);

    function PRECISION() external view returns (uint256);

    function addWhitelist(address _whitelistee) external;

    function adjustWhitelist(
        address[] memory _candidates,
        bool[] memory _status
    ) external;

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function alterExitRatios(
        uint256 _newExitRatio,
        uint256 _newVeExitRatio
    ) external;

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function changeMaximumVestingLength(uint256 _maxVest) external;

    function changeMinimumVestingLength(uint256 _minVest) external;

    function changeVeMaximumVestingLength(uint256 _veMax) external;

    function changeWhitelistOperator(address _newOperator) external;

    function convertRam(uint256 _amount) external;

    function createVest(uint256 _amount) external;

    function decimals() external view returns (uint8);

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) external returns (bool);

    function enneadWhitelist() external view returns (address);

    function exitRatio() external view returns (uint256);

    function exitVest(uint256 _vestID, bool _ve) external returns (bool);

    function getBalanceResiding() external view returns (uint256);

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) external returns (bool);

    function initialize(
        address _timelock,
        address _multisig,
        address _whitelistOperator,
        address _enneadWhitelist
    ) external;

    function instantExit(uint256 _amount) external;

    function isWhitelisted(address) external view returns (bool);

    function maxVest() external view returns (uint256);

    function migrateEnneadWhitelist(address _enneadWhitelist) external;

    function migrateMultisig(address _multisig) external;

    function migrateTimelock(address _timelock) external;

    function minVest() external view returns (uint256);

    function multisig() external view returns (address);

    function multisigRedeem(uint256 _amount) external;

    function name() external view returns (string memory);

    function ram() external view returns (address);

    function reinitializeVestingParameters(
        uint256 _min,
        uint256 _max,
        uint256 _veMax
    ) external;

    function removeWhitelist(address _whitelistee) external;

    function rescueTrappedTokens(
        address[] memory _tokens,
        uint256[] memory _amounts
    ) external;

    function symbol() external view returns (string memory);

    function syncAndCheckIsWhitelisted(
        address _address
    ) external returns (bool);

    function timelock() external view returns (address);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function usersTotalVests(address _user) external view returns (uint256);

    function veExitRatio() external view returns (uint256);

    function veMaxVest() external view returns (uint256);

    function veRam() external view returns (address);

    function vestInfo(
        address user,
        uint256
    )
        external
        view
        returns (uint256 amount, uint256 start, uint256 maxEnd, uint256 vestID);

    function voter() external view returns (address);

    function whitelistOperator() external view returns (address);

    function xRamConvertToNft(
        uint256 _amount
    ) external returns (uint256 veRamTokenId);

    function xRamIncreaseNft(uint256 _amount, uint256 _tokenID) external;
}

