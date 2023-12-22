// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;

import "./IPledgeManager.sol";
import "./ILiquidationPool.sol";
import "./IDCT.sol";

import "./TransferHelper.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";


contract PledgeManager is IPledgeManager, ReentrancyGuardUpgradeable, OwnableUpgradeable {

    IDCT internal dctToken;

    ILiquidationPool internal liquidationPool;

    address internal feesDistributor;
    address internal liquidator;
    address internal signer;

    // client -> pledgeId -> Pledge
    mapping(address => mapping(uint256 => Pledge)) internal pledges;

    enum Status {
        nonExistent,
        active,
        closedByLiquidation
    }

    struct Pledge {
        address[] collTokens;
        mapping(address => uint256) colls;
        uint256 debt;
        Status status;
        uint256 nonce;
    }

    enum PledgeOperation {
        open,
        update,
        liquidation
    }

    struct SignatureVerifyParams {
        address client;
        uint256 pledgeId;
        uint256 debtChange;
        bool isDeptIncreases;
        uint256 accruedFees;
        Collateral[] collsIn;
        Collateral[] collsOut;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event PledgeUpdated(
        address indexed client,
        uint256 indexed pledgeId,
        uint256 debtChange,
        bool isDebtIncrease,
        uint256 accruedFees,
        Collateral[] collsIn,
        Collateral[] collsOut,
        PledgeOperation operation
    );

    error PM_PLEDGE_STATUS_INCORRECT();
    error PM_DEADLINE();
    error PM_NOT_LIQUIDATOR();
    error PM_INVALID_SIGNATURE();
    error PM_REMOVE_TOO_MUCH();
    error PM_REDEEM_TOO_MUCH();


    function initialize(
        address _dctToken,
        address _liquidationPool,
        address _feesDistributor,
        address _liquidator,
        address _signer
    ) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        dctToken        = IDCT(_dctToken);
        liquidationPool = ILiquidationPool(_liquidationPool);

        feesDistributor = _feesDistributor;
        liquidator      = _liquidator;
        signer          = _signer;
    }

    function setFeesDistributor(address _address) external onlyOwner {
        feesDistributor = _address;
    }

    function setLiquidator(address _address) external onlyOwner {
        liquidator = _address;
    }

    function setSigner(address _address) external onlyOwner {
        signer = _address;
    }

    /**
     * @notice Create new Pledge
     *
     * @param _pledgeId Uniq id of the pledge
     * @param _debt Debt of the pledge
     * @param _colls Colls of the pledge tokens and amounts
     * @param _deadline Deadline of the transaction
     * @param _v V of the signature
     * @param _r R of the signature
     * @param _s S of the signature
     */
    function openPledge(
        uint256 _pledgeId,
        uint256 _debt,
        Collateral[] memory _colls,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override nonReentrant {

        _validSignature(SignatureVerifyParams({
            client: msg.sender,
            pledgeId: _pledgeId,
            debtChange: _debt,
            isDeptIncreases: true,
            accruedFees: 0,
            collsIn: _colls,
            collsOut: new Collateral[](0),
            deadline: _deadline,
            v: _v,
            r: _r,
            s: _s
        }));

        _requirePledgeStatus(msg.sender, _pledgeId, Status.nonExistent);

        pledges[msg.sender][_pledgeId].status = Status.active;
        pledges[msg.sender][_pledgeId].nonce += 1;

        _transferCollateralsIntoPledge(msg.sender, _pledgeId, _colls);

        _changePledgeDebt(msg.sender, _pledgeId, _debt, true);

        emit PledgeUpdated(
            msg.sender,
            _pledgeId,
            _debt,
            true,
            0,
            _colls,
            new Collateral[](0),
            PledgeOperation.open
        );
    }

    /**
     * @notice Update Pledge
     *
     * @param _pledgeId Uniq id of the pledge
     * @param _debtChange Debt change of the pledge
     * @param _isDebtIncrease Is debt increase or decrease
     * @param _accruedFees Accrued fees of the pledge - will be transferred from user to feesDistributor
     * @param _collsIn Colls of the pledge tokens and amounts to transfer into pledge
     * @param _collsOut Colls of the pledge tokens and amounts to transfer out of pledge
     * @param _deadline Deadline of the transaction
     * @param _v V of the signature
     * @param _r R of the signature
     * @param _s S of the signature
     */
    function updatePledge(
        uint256 _pledgeId,
        uint256 _debtChange,
        bool _isDebtIncrease,
        uint256 _accruedFees,
        Collateral[] memory _collsIn,
        Collateral[] memory _collsOut,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override nonReentrant {

        _validSignature(SignatureVerifyParams({
            client: msg.sender,
            pledgeId: _pledgeId,
            debtChange: _debtChange,
            isDeptIncreases: _isDebtIncrease,
            accruedFees: _accruedFees,
            collsIn: _collsIn,
            collsOut: _collsOut,
            deadline: _deadline,
            v: _v,
            r: _r,
            s: _s
        }));

        _requirePledgeStatus(msg.sender, _pledgeId, Status.active);

        _transferCollateralsIntoPledge(msg.sender, _pledgeId, _collsIn);
        _transferCollateralsOutOfPledge(msg.sender, _pledgeId, _collsOut, msg.sender);

        _changePledgeDebt(msg.sender, _pledgeId, _debtChange, _isDebtIncrease);

        // on "Repay debt" action: transfer _accruedFees from user to feesDistributor
        if (!_isDebtIncrease && _debtChange > 0 && _accruedFees > 0) {
            TransferHelper.safeTransferFrom(address(dctToken), msg.sender, feesDistributor, _accruedFees);
        }

        pledges[msg.sender][_pledgeId].nonce += 1;

        emit PledgeUpdated(
            msg.sender,
            _pledgeId,
            _debtChange,
            _isDebtIncrease,
            _accruedFees,
            _collsIn,
            _collsOut,
            PledgeOperation.update
        );
    }

    /**
     * @notice Liquidate Pledge
     *
     * Liquidator should transfer collaterals to liquidationPool
     * And transfer current debt and accruedFees to liquidationPool as debt
     *
     * After that liquidator can withdraw collateral from liquidationPool, sell and repay debt
     * Accrued fees will be transferred to feesDistributor once liquidator repays debt
     *
     * @param _client The address of the user
     * @param _pledgeId Id of user pledge
     * @param _accruedFees Accrued fees of the pledge - will be transferred to liquidationPool as debt
     * @param _deadline Deadline of the transaction
     * @param _v V of the signature
     * @param _r R of the signature
     * @param _s S of the signature
     */
    function liquidatePledge(
        address _client,
        uint256 _pledgeId,
        uint256 _accruedFees,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        if (msg.sender != liquidator) { revert PM_NOT_LIQUIDATOR(); }

        _requirePledgeStatus(_client, _pledgeId, Status.active);

        // get current pledge state and calculate its VC and ICR
        (Collateral[] memory colls, uint256 debt) = getPledgeState(_client, _pledgeId);

        _validSignature(SignatureVerifyParams({
            client: _client,
            pledgeId: _pledgeId,
            isDeptIncreases: false,
            debtChange: debt,
            accruedFees: _accruedFees,
            collsIn: new Collateral[](0),
            collsOut: colls,
            deadline: _deadline,
            v: _v,
            r: _r,
            s: _s
        }));

        _transferCollateralsOutOfPledge(_client, _pledgeId, colls, address(liquidationPool));

        // close pledge debt from liquidator balance
        liquidationPool.addDebtToPool(debt, _accruedFees);

        // TODO: transfer _accruedFees from user/liquidationPool to feesDistributor ???

        // closes pledge by liquidation
        pledges[_client][_pledgeId].status = Status.closedByLiquidation;
        pledges[_client][_pledgeId].debt   = 0;
        pledges[_client][_pledgeId].nonce += 1;

        emit PledgeUpdated(
            _client,
            _pledgeId,
            debt,
            false,
            _accruedFees,
            new Collateral[](0),
            colls,
            PledgeOperation.liquidation
        );
    }

    /**
     * Gets current pledge state as colls and debt
     *
     * @param _client The address of the user
     * @param _pledgeId Id of user pledge
     * @return colls - Colls of the pledge tokens and amounts
     * @return debt - Debt of the pledge
     */
    function getPledgeState(address _client, uint256 _pledgeId) public view returns (Collateral[] memory, uint256) {
        uint256 collsLen = pledges[_client][_pledgeId].collTokens.length;
        uint256 debt = pledges[_client][_pledgeId].debt;

        Collateral[] memory colls = new Collateral[](collsLen);
        for (uint256 i = 0; i < collsLen;) {
            address token = pledges[_client][_pledgeId].collTokens[i];
            colls[i] = Collateral(token, pledges[_client][_pledgeId].colls[token]);
            unchecked {
                i++;
            }
        }

        return (colls, debt);
    }

    /**
     * Gets current pledge status
     *
     * @param _client The address of the user
     * @param _pledgeId Id of user pledge
     * @return status - Status of the pledge
     */
    function getPledgeStatus(address _client, uint256 _pledgeId) external view returns (uint256) {
        return uint256(pledges[_client][_pledgeId].status);
    }

    /**
     * Gets current pledge nonce
     *
     * @param _client The address of the user
     * @param _pledgeId Id of user pledge
     * @return nonce - Nonce of the pledge
     */
    function getPledgeNonce(address _client, uint256 _pledgeId) external view returns (uint256) {
        return pledges[_client][_pledgeId].nonce;
    }


    // -- Internal functions -- //

    function _transferCollateralsIntoPledge(address _client, uint256 _pledgeId, Collateral[] memory _colls) internal {
        uint256 collsLen = _colls.length;

        for (uint256 i; i < collsLen;) {
            if (_colls[i].amount > 0) {
                if (pledges[_client][_pledgeId].colls[_colls[i].token] == 0) {
                    pledges[_client][_pledgeId].collTokens.push(_colls[i].token);
                }
                pledges[_client][_pledgeId].colls[_colls[i].token] += _colls[i].amount;

                TransferHelper.safeTransferFrom(_colls[i].token, msg.sender, address(this), _colls[i].amount);
            }
            unchecked {
                i++;
            }
        }
    }

    function _transferCollateralsOutOfPledge(address _client, uint256 _pledgeId, Collateral[] memory _collsOut, address _receiver) internal {
        uint256 collsOutLen = _collsOut.length;
        for (uint256 i; i < collsOutLen;) {
            if (_collsOut[i].amount > 0) {
                if (pledges[_client][_pledgeId].colls[_collsOut[i].token] < _collsOut[i].amount) {
                    revert PM_REMOVE_TOO_MUCH();
                }

                pledges[_client][_pledgeId].colls[_collsOut[i].token] -= _collsOut[i].amount;

                if (pledges[_client][_pledgeId].colls[_collsOut[i].token] == 0) {
                    for (uint256 j = 0; j < pledges[_client][_pledgeId].collTokens.length;) {
                        if (pledges[_client][_pledgeId].collTokens[j] == _collsOut[i].token) {
                            pledges[_client][_pledgeId].collTokens[j] = pledges[_client][_pledgeId].collTokens[
                                pledges[_client][_pledgeId].collTokens.length - 1
                            ];
                            pledges[_client][_pledgeId].collTokens.pop();
                            break;
                        }
                        unchecked {
                            j++;
                        }
                    }
                }

                TransferHelper.safeTransfer(_collsOut[i].token, _receiver, _collsOut[i].amount);
            }

            unchecked {
                i++;
            }
        }
    }

    /**
     * Verify backend signature - this is to ensure that the platform backend is the one calling
     * this function and not someone else outside of the platform
     */
    function _validSignature(SignatureVerifyParams memory input) internal view {
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(
            input.client,
            input.pledgeId,
            input.isDeptIncreases,
            input.debtChange,
            input.accruedFees,
            abi.encode(input.collsIn),
            abi.encode(input.collsOut),
            pledges[input.client][input.pledgeId].nonce,
            input.deadline
        ))));

        if (signer != ecrecover(prefixedHashMessage, input.v, input.r, input.s)) {
            revert PM_INVALID_SIGNATURE();
        }

        if (input.deadline < block.timestamp) {
            revert PM_DEADLINE();
        }
    }

    function _requirePledgeStatus(address _client, uint256 _pledgeId, Status _status) internal view {
        if (pledges[_client][_pledgeId].status != _status) {
            revert PM_PLEDGE_STATUS_INCORRECT();
        }
    }

    function _changePledgeDebt(address _client, uint256 _pledgeId, uint256 _debtChange, bool _isDebtIncrease) internal {
        if (_debtChange > 0) {
            if (_isDebtIncrease) {
                pledges[_client][_pledgeId].debt += _debtChange;
                dctToken.mint(_client, _debtChange);
            } else {
                if (pledges[_client][_pledgeId].debt < _debtChange) {
                    revert PM_REDEEM_TOO_MUCH();
                }

                pledges[_client][_pledgeId].debt -= _debtChange;
                dctToken.burn(_client, _debtChange);
            }
        }
    }
}

