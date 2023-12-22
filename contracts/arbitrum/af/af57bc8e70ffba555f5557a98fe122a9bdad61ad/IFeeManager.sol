pragma solidity 0.8.18;

interface IFeeManager {
    function distribute(address) external;
    function setTreasuryShare(uint16) external;
    function setTeamShare(uint16) external;
    function setStakingShare(uint16) external;

    function treasury() external returns(address);
    function team() external returns(address);
    function staking() external returns(address);

    function treasuryShare() external returns(uint16);
    function stakingShare() external returns(uint16);
    function teamShare() external returns(uint16);
}

