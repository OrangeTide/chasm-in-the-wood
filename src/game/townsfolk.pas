unit townsfolk;
{ The people of Brackenridge. They are peaceful entities the turn loop never fights:  }
{ the innkeeper, who trades rest for coin; the trader, who buys what the dungeon gives  }
{ up; the reeve, who keeps the hamlet; and a villager with rumours. This unit holds     }
{ their roles, their look, and the builder that stands them by their doors; the trade   }
{ itself lives in the turn loop, which has the player's purse.                          }

{$mode objfpc}{$H+}

interface

uses
  town, content, entities;

const
  ROLE_INNKEEPER = 0;
  ROLE_TRADER    = 1;
  ROLE_REEVE     = 2;
  ROLE_VILLAGER  = 3;

  INN_REST_COST  = 5;   { gold the innkeeper asks for a full night's rest }

{ Replace the entity set with the hamlet's townsfolk, placed by the layout. }
procedure TownsfolkBuild(var es: TEntitySet; const lay: TTownLayout);

{ A townsperson's short title, for the combat/dialogue log. }
function TownRoleName(role: LongInt): String;

{ The line a townsperson opens with when the player speaks to them. }
function TownGreeting(role: LongInt): String;

implementation

procedure Add(var es: TEntitySet; role, cx, cy: LongInt; r, g, b: Single);
var
  e: TEntity;
begin
  e.Kind := enTownsfolk;
  e.Cx := cx; e.Cy := cy;
  e.Role := role;
  e.DefIdx := 0;
  e.Size := szMedium;
  e.R := r; e.G := g; e.B := b;
  e.OrigRx := 0; e.OrigRy := 0; e.OrigIdx := 0;
  e.Hp := 0; e.MaxHp := 0; e.Energy := 0;
  e.Alive := True;
  e.Awake := False;
  EntityAppend(es, e);
end;

procedure TownsfolkBuild(var es: TEntitySet; const lay: TTownLayout);
begin
  EntitiesClear(es);
  Add(es, ROLE_INNKEEPER, lay.Innkeeper.X, lay.Innkeeper.Y, 0.80, 0.60, 0.35);
  Add(es, ROLE_TRADER,    lay.Trader.X,    lay.Trader.Y,    0.55, 0.45, 0.80);
  Add(es, ROLE_REEVE,     lay.Reeve.X,     lay.Reeve.Y,     0.75, 0.30, 0.30);
  Add(es, ROLE_VILLAGER,  lay.Villager.X,  lay.Villager.Y,  0.45, 0.70, 0.75);
end;

function TownRoleName(role: LongInt): String;
begin
  case role of
    ROLE_INNKEEPER: TownRoleName := 'Innkeeper';
    ROLE_TRADER:    TownRoleName := 'Trader';
    ROLE_REEVE:     TownRoleName := 'Reeve';
  else              TownRoleName := 'Villager';
  end;
end;

function TownGreeting(role: LongInt): String;
begin
  case role of
    ROLE_INNKEEPER:
      TownGreeting := 'Innkeeper: A bed and a hot meal, never on credit.';
    ROLE_TRADER:
      TownGreeting := 'Trader: Show me what you brought up from below.';
    ROLE_REEVE:
      TownGreeting := 'Reeve: Brackenridge is grateful to any who descend.';
  else
    TownGreeting := 'Villager: The third one who went down never came back.';
  end;
end;

end.
