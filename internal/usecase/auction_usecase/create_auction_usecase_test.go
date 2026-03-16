package auction_usecase

import (
	"context"
	"fullcycle-auction_go/internal/entity/auction_entity"
	"fullcycle-auction_go/internal/entity/bid_entity"
	"fullcycle-auction_go/internal/internal_error"
	"sync"
	"testing"
	"time"
)

type auctionRepositoryStub struct {
	mu           sync.Mutex
	lastAuction  *auction_entity.Auction
	lastDuration time.Duration
	auctions     map[string]*auction_entity.Auction
}

func (a *auctionRepositoryStub) CreateAuction(
	_ context.Context,
	auctionEntity *auction_entity.Auction,
	duration time.Duration) *internal_error.InternalError {
	a.mu.Lock()
	a.lastAuction = auctionEntity
	a.lastDuration = duration
	if a.auctions == nil {
		a.auctions = make(map[string]*auction_entity.Auction)
	}
	a.auctions[auctionEntity.Id] = &auction_entity.Auction{
		Id:          auctionEntity.Id,
		ProductName: auctionEntity.ProductName,
		Category:    auctionEntity.Category,
		Description: auctionEntity.Description,
		Condition:   auctionEntity.Condition,
		Status:      auction_entity.Active,
		Timestamp:   auctionEntity.Timestamp,
	}
	a.mu.Unlock()

	go func(auctionId string, closeDuration time.Duration) {
		time.Sleep(closeDuration)
		a.mu.Lock()
		if auction, ok := a.auctions[auctionId]; ok {
			auction.Status = auction_entity.Completed
		}
		a.mu.Unlock()
	}(auctionEntity.Id, duration)

	return nil
}

func (a *auctionRepositoryStub) FindAuctions(
	_ context.Context,
	_ auction_entity.AuctionStatus,
	_, _ string) ([]auction_entity.Auction, *internal_error.InternalError) {
	return nil, nil
}

func (a *auctionRepositoryStub) FindAuctionById(
	_ context.Context, id string) (*auction_entity.Auction, *internal_error.InternalError) {
	a.mu.Lock()
	defer a.mu.Unlock()

	auction, ok := a.auctions[id]
	if !ok {
		return nil, internal_error.NewNotFoundError("auction not found")
	}

	return &auction_entity.Auction{
		Id:          auction.Id,
		ProductName: auction.ProductName,
		Category:    auction.Category,
		Description: auction.Description,
		Condition:   auction.Condition,
		Status:      auction.Status,
		Timestamp:   auction.Timestamp,
	}, nil
}

type bidRepositoryStub struct{}

func (b *bidRepositoryStub) CreateBid(
	_ context.Context,
	_ []bid_entity.Bid) *internal_error.InternalError {
	return nil
}

func (b *bidRepositoryStub) FindBidByAuctionId(
	_ context.Context, _ string) ([]bid_entity.Bid, *internal_error.InternalError) {
	return nil, nil
}

func (b *bidRepositoryStub) FindWinningBidByAuctionId(
	_ context.Context, _ string) (*bid_entity.Bid, *internal_error.InternalError) {
	return nil, nil
}

func TestCreateAuctionUseCaseAutoCloseAuctionByDuration(t *testing.T) {
	t.Setenv("AUCTION_DURATION", "1s")

	auctionRepo := &auctionRepositoryStub{}
	useCase := NewAuctionUseCase(auctionRepo, &bidRepositoryStub{})

	err := useCase.CreateAuction(context.Background(), AuctionInputDTO{
		ProductName: "Notebook",
		Category:    "Eletronicos",
		Description: "Notebook usado em bom estado para testes automatizados.",
		Condition:   ProductCondition(auction_entity.Used),
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if auctionRepo.lastDuration != time.Second {
		t.Fatalf("expected duration %s, got %s", time.Second, auctionRepo.lastDuration)
	}

	if auctionRepo.lastAuction == nil {
		t.Fatal("expected auction to be created")
	}

	auctionBeforeClose, err := useCase.FindAuctionById(context.Background(), auctionRepo.lastAuction.Id)
	if err != nil {
		t.Fatalf("expected to find auction, got %v", err)
	}

	if auctionBeforeClose.Status != AuctionStatus(auction_entity.Active) {
		t.Fatalf("expected auction status %d before close, got %d", auction_entity.Active, auctionBeforeClose.Status)
	}

	time.Sleep(2 * time.Second)

	auctionAfterClose, err := useCase.FindAuctionById(context.Background(), auctionRepo.lastAuction.Id)
	if err != nil {
		t.Fatalf("expected to find auction after wait, got %v", err)
	}

	if auctionAfterClose.Status != AuctionStatus(auction_entity.Completed) {
		t.Fatalf("expected auction status %d after close, got %d", auction_entity.Completed, auctionAfterClose.Status)
	}
}

func TestCreateAuctionUseCaseUsesDefaultDurationWhenEnvIsInvalid(t *testing.T) {
	t.Setenv("AUCTION_DURATION", "invalid-duration")

	auctionRepo := &auctionRepositoryStub{}
	useCase := NewAuctionUseCase(auctionRepo, &bidRepositoryStub{})

	err := useCase.CreateAuction(context.Background(), AuctionInputDTO{
		ProductName: "Notebook",
		Category:    "Eletronicos",
		Description: "Notebook usado em bom estado para testes automatizados.",
		Condition:   ProductCondition(auction_entity.Used),
	})
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if auctionRepo.lastDuration != defaultAuctionDuration {
		t.Fatalf("expected duration %s, got %s", defaultAuctionDuration, auctionRepo.lastDuration)
	}
}
