pragma solidity 0.8.17;

interface IMarket {
    enum MarketStatus {
        Trading,
        Payingout
    }
    struct Insurance {
        uint256 id; //each insuance has their own id
        uint48 startTime; //timestamp of starttime
        uint48 endTime; //timestamp of endtime
        uint256 amount; //insured amount
        bytes32 target; //target id in bytes32
        address insured; //the address holds the right to get insured
        address agent; //address have control. can be different from insured.
        bool status; //true if insurance is not expired or redeemed
    }

    function marketStatus() external view returns (MarketStatus);

    function allInsuranceCount() external view returns (uint256);

    function insurances(uint256) external view returns (Insurance memory);

    function unlockBatch(uint256[] calldata _ids) external;

    function unlock(uint256 _id) external;
}

