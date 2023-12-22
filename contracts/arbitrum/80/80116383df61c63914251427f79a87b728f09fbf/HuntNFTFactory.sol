// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./OwnableUpgradeable.sol";
import "./IERC1155.sol";
import "./IERC721.sol";

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";

import "./IHuntGameRandomRequester.sol";
import "./IHuntNFTFactory.sol";
import "./HuntGameDeployer.sol";
import "./ReentrancyGuard.sol";
import "./IBulletOracle.sol";

contract HuntNFTFactory is OwnableUpgradeable, VRFConsumerBaseV2, HuntGameDeployer, ReentrancyGuard, IHuntNFTFactory {
    address constant ETH_PAYMENT = address(0);

    IHuntBridge public override getHuntBridge;
    IHunterAssetManager public override getHunterAssetManager;
    IFeeManager public override getFeeManager;
    IBulletOracle getBulletOracle;

    uint64 public override totalGames;
    mapping(uint64 => address) public getGameById;
    mapping(address => bool) public override isHuntGame;
    mapping(address => bool) public override isPaymentEnabled;

    DeployParams deployParams;
    bytes public override tempValidatorParams;

    /// @dev vrf states
    // Your subscription ID.
    uint64 vrfSubscriptionId;
    VRFCoordinatorV2Interface vrfCordinator;
    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 vrfKeyHash;
    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 public callbackGasLimit;

    // The default is 3, but you can set this higher.
    uint16 public requestConfirmations;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 constant numWords = 1;
    // Your rquest ID.
    mapping(uint256 => address) public getRequestGame;

    /// @dev GOERLI COORDINATOR: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
    function initialize(
        address _beacon,
        uint64 _vrfSubscriptionId,
        address _vrfCoordinator,
        bytes32 _vrfKeyHash
    ) public initializer {
        __Ownable_init();
        beacon = _beacon;
        VRFConsumerBaseV2._initialize(_vrfCoordinator);

        vrfSubscriptionId = _vrfSubscriptionId;
        vrfCordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        vrfKeyHash = _vrfKeyHash;

        callbackGasLimit = 100000;
        requestConfirmations = 32;
    }

    function createWithPayETHHuntGame(
        address gameOwner,
        address wantedGame,
        IHunterValidator hunterValidator,
        IHuntGame.NFTStandard nftStandard,
        uint64 totalBullets,
        uint256 bulletPrice,
        address nftContract,
        uint64 originChain,
        uint256 tokenId,
        uint64 ddl,
        bytes memory registerParams
    ) public payable {
        address _game = createETHHuntGame(
            gameOwner,
            wantedGame,
            hunterValidator,
            nftStandard,
            totalBullets,
            bulletPrice,
            nftContract,
            originChain,
            tokenId,
            ddl,
            registerParams
        );
        if (originChain != block.chainid) {
            address nft = IGlobalNftDeployer(getHuntBridge).calcAddr(originChain, nftContract);
            if (nftStandard == IHuntGame.NFTStandard.GlobalERC721) {
                IERC721(nft).transferFrom(msg.sender, _game, tokenId);
            } else {
                IERC1155(nft).safeTransferFrom(msg.sender, _game, tokenId, 1, "");
            }
            IHuntGame(_game).startHunt();
        }
    }

    function createETHHuntGame(
        address gameOwner,
        address wantedGame,
        IHunterValidator hunterValidator,
        IHuntGame.NFTStandard nftStandard,
        uint64 totalBullets,
        uint256 bulletPrice,
        address nftContract,
        uint64 originChain,
        uint256 tokenId,
        uint64 ddl,
        bytes memory registerParams
    ) public payable nonReentrant returns (address _game) {
        require(tempValidatorParams.length == 0);
        tempValidatorParams = registerParams;
        if (gameOwner == address(0)) {
            gameOwner = msg.sender;
        }
        uint64 _gameId = totalGames + 1;
        totalGames += 1;
        deployParams = DeployParams(
            hunterValidator,
            nftStandard,
            totalBullets,
            bulletPrice,
            nftContract,
            originChain,
            address(0),
            this,
            tokenId,
            _gameId,
            ddl,
            gameOwner
        );
        _game = _createHuntGame();
        delete deployParams;
        if (wantedGame != address(0)) {
            require(_game == wantedGame, string(abi.encodePacked("wanted ", wantedGame, ",but got ", _game)));
        }
        delete tempValidatorParams;
    }

    function createHuntGame(
        address gameOwner,
        address wantedGame,
        IHunterValidator hunterValidator,
        IHuntGame.NFTStandard nftStandard,
        uint64 totalBullets,
        uint256 bulletPrice,
        address nftContract,
        uint64 originChain,
        address payment,
        uint256 tokenId,
        uint64 ddl,
        bytes memory registerParams
    ) public payable nonReentrant returns (address _game) {
        require(tempValidatorParams.length == 0);
        require(isPaymentEnabled[payment], "PAYMENT_ERR");
        tempValidatorParams = registerParams;
        uint64 _gameId = totalGames + 1;
        totalGames += 1;
        deployParams = DeployParams(
            hunterValidator,
            nftStandard,
            totalBullets,
            bulletPrice,
            nftContract,
            originChain,
            payment,
            this,
            tokenId,
            _gameId,
            ddl,
            gameOwner
        );
        _game = _createHuntGame();
        delete deployParams;
        if (wantedGame != address(0)) {
            require(_game == wantedGame, string(abi.encodePacked("wanted ", wantedGame, ",but got ", _game)));
        }
        delete tempValidatorParams;
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords() external returns (uint256 requestId) {
        require(isHuntGame[msg.sender], "only hunt game");
        // Will revert if subscription is not set and funded.
        requestId = vrfCordinator.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        require(getRequestGame[requestId] == address(0), "already registered");
        getRequestGame[requestId] = msg.sender;
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        IHuntGameRandomRequester(getRequestGame[_requestId]).fillRandom(_randomWords[0]);
    }

    function huntGameClaimPayment(address _hunter, address _erc20, uint256 _amount) public {
        require(isHuntGame[msg.sender] && _erc20 != address(0));
        IERC20(_erc20).transferFrom(_hunter, msg.sender, _amount);
    }

    /// dao
    function setCallbackGasLimit(uint32 l) public onlyOwner {
        callbackGasLimit = l;
    }

    function setRequestConfirmations(uint16 l) public onlyOwner {
        requestConfirmations = l;
    }

    function enablePayment(address payment, bool enable) public onlyOwner {
        isPaymentEnabled[payment] = enable;
    }

    function setHuntBridge(IHuntBridge i) public onlyOwner {
        getHuntBridge = i;
    }

    function setHunterAssetManager(IHunterAssetManager i) public onlyOwner {
        getHunterAssetManager = i;
    }

    function setFeeManager(IFeeManager i) public onlyOwner {
        getFeeManager = i;
    }

    function setBulletOracle(IBulletOracle i) public onlyOwner {
        getBulletOracle = i;
    }

    function prepareSubBridgeParam() internal {
        if (msg.sender != address(getHuntBridge)) {
            return;
        }
        // bridge exceed total bullet will be recap to max bullet, make sure the value of asset not changed
        uint64 maxBullet = getBulletOracle.getMaxBullet(
            deployParams.owner,
            deployParams.originChain,
            deployParams.nftContract
        );
        if (deployParams.totalBullets > maxBullet) {
            uint256 value = deployParams.totalBullets * deployParams.bulletPrice;
            deployParams.totalBullets = maxBullet;
            deployParams.bulletPrice = value / maxBullet;
        }
        //too old timestamp just append 12 hours, which happens when creator set
        // a narrow ddl and layerzero relayer have a heavy network.But to avoid long time price loss of nft, creator will try set a so closed ddl.
        // so just make game near timeout
        if (deployParams.ddl <= block.timestamp) {
            deployParams.ddl = uint64(block.timestamp) + 1;
        }
        // @notice validator params should only be guaranteed by application, so wrong params have to revoke message itself
    }

    function _createHuntGame() internal returns (address _game) {
        prepareSubBridgeParam();
        require(deployParams.ddl > block.timestamp, "ERR_DDL");
        require(deployParams.totalBullets > 0, "ERR_BULLET");
        require(
            deployParams.totalBullets <=
                getBulletOracle.getMaxBullet(
                    msg.sender == address(getHuntBridge) ? deployParams.owner : msg.sender,
                    deployParams.originChain,
                    deployParams.nftContract
                ),
            "TOO_LARGE_BULLET"
        );
        if (msg.sender != address(getHuntBridge)) {
            //bridge already paid in sub chain
            getFeeManager.payBaseFee{ value: msg.value }();
        }
        _game = _deploy(deployParams);
        getGameById[deployParams.gameId] = _game;
        isHuntGame[_game] = true;
        emit HuntGameCreated(
            deployParams.owner,
            _game,
            deployParams.gameId,
            address(deployParams.hunterValidator),
            deployParams.nftStandard,
            deployParams.totalBullets,
            deployParams.bulletPrice,
            deployParams.nftContract,
            deployParams.originChain,
            deployParams.getPayment,
            deployParams.tokenId,
            deployParams.ddl,
            tempValidatorParams
        );
        if (deployParams.originChain == block.chainid) {
            //pay nft to the game and then start game
            _payNativeNFT(deployParams.nftStandard, deployParams.nftContract, deployParams.tokenId, _game);
            IHuntGame(_game).startHunt();
        }
    }

    function _payNativeNFT(
        IHuntGame.NFTStandard nftStandard,
        address nftContract,
        uint256 tokenId,
        address _recipient
    ) internal {
        if (nftStandard == IHuntGame.NFTStandard.GlobalERC721) {
            /// native chain
            IERC721(nftContract).transferFrom(msg.sender, _recipient, tokenId);
        } else if (nftStandard == IHuntGame.NFTStandard.GlobalERC1155) {
            IERC1155(nftContract).safeTransferFrom(msg.sender, _recipient, tokenId, 1, "");
        }
    }
}

