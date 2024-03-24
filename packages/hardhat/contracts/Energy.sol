// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "hardhat/console.sol";

contract EnergyTradeHub is ERC721URIStorage, ReentrancyGuard, AccessControl {
	using Address for address payable;

	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
	bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER_ROLE");
	bytes32 public constant CONSUMER_ROLE = keccak256("CONSUMER_ROLE");

	uint256 public tokenCount = 0;

	struct EnergyContract {
		uint256 id;
		address issuer;
		address owner;
		uint256 energyAmountMWh;
		uint256 pricePerMWh;
		uint256 startDate;
		uint256 endDate;
		string sourceType;
		string deliveryPoint;
		bool isActive;
		string contractTermsHash;
	}

	struct TokenSale {
		bool isForSale;
		uint256 price;
	}

	struct Escrow {
		address buyer;
		uint256 amount;
		bool fundsReleased;
	}

	mapping(uint256 => EnergyContract) public tokens;
	mapping(uint256 => TokenSale) public tokenSales;
	mapping(uint256 => Escrow) public escrows;

	event TokenCreated(
		uint256 id,
		address issuer,
		address owner,
		uint256 energyAmountMWh,
		uint256 pricePerMWh,
		uint256 startDate,
		uint256 endDate,
		string sourceType,
		string deliveryPoint,
		bool isActive,
		string contractTermsHash
	);

	event TokenListedForSale(uint256 id, uint256 price);
	event TokenSaleWithdrawn(uint256 id);
	event TokenPurchased(uint256 id, address buyer, uint256 price);
	event TokenBurned(uint256 id, address burner);
	event EscrowCreated(uint256 tokenId, uint256 amount);
	event EscrowReleased(uint256 tokenId);
	event EscrowRefunded(uint256 tokenId);

	constructor() ERC721("EnergyTradeHubToken", "ETHB") {
		
		console.log("Sender",msg.sender);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Setup other roles
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PROVIDER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(CONSUMER_ROLE, ADMIN_ROLE);

        // Grant the deployer also as an admin, provider, and consumer for demonstration purposes
        grantRole(ADMIN_ROLE, msg.sender);
        grantRole(PROVIDER_ROLE, msg.sender);
        grantRole(CONSUMER_ROLE, msg.sender);

	}

	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC721, AccessControl) returns (bool) {
		return
			ERC721.supportsInterface(interfaceId) ||
			AccessControl.supportsInterface(interfaceId);
	}

	function addConsumer(address consumer) public {
		require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
		grantRole(CONSUMER_ROLE, consumer);
	}

	function addProvider(address provider) public {
		require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
		grantRole(PROVIDER_ROLE, provider);
	}

	modifier onlyProvider() {
		require(hasRole(PROVIDER_ROLE, msg.sender), "Caller is not a provider");
		_;
	}

	function createToken(
		address issuer,
		uint256 energyAmountMWh,
		uint256 pricePerMWh,
		uint256 startDate,
		uint256 endDate,
		string memory sourceType,
		string memory deliveryPoint,
		string memory contractTermsHash,
		string memory tokenURI
	) public onlyProvider returns (uint256) {
		require(startDate < endDate, "Start date must be before end date.");
		require(
			energyAmountMWh > 0,
			"Energy amount must be greater than 0 MWh."
		);

		tokenCount++;
		uint256 newTokenId = tokenCount;
		_mint(issuer, newTokenId);
		_setTokenURI(newTokenId, tokenURI);

		tokens[newTokenId] = EnergyContract(
			newTokenId,
			issuer,
			issuer, // Initially, the issuer is the owner
			energyAmountMWh,
			pricePerMWh,
			startDate,
			endDate,
			sourceType,
			deliveryPoint,
			true, // isActive
			contractTermsHash
		);

		emit TokenCreated(
			newTokenId,
			issuer,
			issuer,
			energyAmountMWh,
			pricePerMWh,
			startDate,
			endDate,
			sourceType,
			deliveryPoint,
			true,
			contractTermsHash
		);
		return newTokenId;
	}

	function listTokenForSale(uint256 tokenId, uint256 price) public {
		require(
			ownerOf(tokenId) == msg.sender,
			"You must own the token to list it for sale."
		);
		tokenSales[tokenId] = TokenSale(true, price);
		emit TokenListedForSale(tokenId, price);
	}

	function withdrawTokenFromSale(uint256 tokenId) public {
		require(
			ownerOf(tokenId) == msg.sender,
			"You must own the token to withdraw it from sale."
		);
		tokenSales[tokenId].isForSale = false;
		emit TokenSaleWithdrawn(tokenId);
	}

	function buyToken(uint256 tokenId) public payable nonReentrant {
		require(tokenSales[tokenId].isForSale, "This token is not for sale.");
		require(
			msg.value >= tokenSales[tokenId].price,
			"Insufficient funds sent."
		);
		escrows[tokenId] = Escrow(msg.sender, msg.value, false);
		tokenSales[tokenId].isForSale = false;

		emit EscrowCreated(tokenId, msg.value);
		emit TokenPurchased(tokenId, msg.sender, tokenSales[tokenId].price);
	}

	function releaseEscrow(uint256 tokenId) public {
		require(
			hasRole(ADMIN_ROLE, msg.sender),
			"Only admin or provider can release funds."
		);
		require(escrows[tokenId].amount > 0, "No escrow for this token.");
		require(!escrows[tokenId].fundsReleased, "Funds already released.");

		address seller = ownerOf(tokenId);
		uint256 amount = escrows[tokenId].amount;
		escrows[tokenId].fundsReleased = true;

		payable(seller).sendValue(amount);
		emit EscrowReleased(tokenId);
	}

	function refundEscrow(uint256 tokenId) public {
		require(
			hasRole(ADMIN_ROLE, msg.sender),
			"Only admin can refund."
		);
		require(escrows[tokenId].amount > 0, "No escrow for this token.");
		require(!escrows[tokenId].fundsReleased, "Funds already released.");

		address buyer = escrows[tokenId].buyer;
		uint256 amount = escrows[tokenId].amount;
		escrows[tokenId].fundsReleased = true;

		payable(buyer).sendValue(amount);
		burnToken(tokenId);
		emit EscrowRefunded(tokenId);
	}

	function burnToken(uint256 tokenId) public {
		require(hasRole(CONSUMER_ROLE, msg.sender), "Caller is not a consumer");
		require(
			ownerOf(tokenId) == msg.sender,
			"You must own the token to burn it."
		);

		// isActive is checked instead of the valid period for simplicity
		require(tokens[tokenId].isActive, "The token is not active.");

		tokens[tokenId].isActive = false; // Deactivate token upon burning
		_burn(tokenId);
		emit TokenBurned(tokenId, msg.sender);
	}
}