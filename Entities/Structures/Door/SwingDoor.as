// Swing Door logic

#include "Hitters.as"
#include "FireCommon.as"
#include "MapFlags.as"
#include "DoorCommon.as"

void onInit(CBlob@ this)
{
	this.getShape().SetRotationsAllowed(false);
	this.getSprite().getConsts().accurateLighting = true;

	this.set_s16(burn_duration , 300);
	//transfer fire to underlying tiles
	this.Tag(spread_fire_tag);

	// this.getCurrentScript().runFlags |= Script::tick_not_attached;
	this.getCurrentScript().tickFrequency = 0;

	//block knight sword
	this.Tag("blocks sword");

	// disgusting HACK
	// for DefaultNoBuild.as
	if (this.getName() == "stone_door")
	{
		this.set_TileType("background tile", CMap::tile_castle_back);

		if (getNet().isServer())
		{
			dictionary harvest;
			harvest.set('mat_stone', 10);
			this.set('harvest', harvest);
		}
	}
	else
	{
		this.set_TileType("background tile", CMap::tile_wood_back);

		if (getNet().isServer())
		{
			dictionary harvest;
			harvest.set('mat_wood', 10);
			this.set('harvest', harvest);
		}
	}
	this.Tag("door");
	this.Tag("blocks water");
	this.Tag("explosion always teamkill"); // ignore 'no teamkill' for explosives
}

void onSetStatic(CBlob@ this, const bool isStatic)
{
	if (!isStatic) return;

	this.getSprite().PlaySound("/build_door.ogg");
	
	int touchingBlobs = this.getTouchingCount();
	for (int a = 0; a < touchingBlobs; a++)
	{
		CBlob@ blob = this.getTouchingByIndex(a);
		if (blob is null)
			continue;

		if (this.getTeamNum() == blob.getTeamNum() && 
			(blob.hasTag("player") || blob.hasTag("vehicle") || blob.hasTag("migrant")))
		{
			OpenDoor(this, blob);
			break;
		}
	}
}

//TODO: fix flags sync and hitting
/*void onDie(CBlob@ this)
{
    SetSolidFlag(this, false);
}*/

bool isOpen(CBlob@ this)
{
	return !this.getShape().getConsts().collidable;
}

void setOpen(CBlob@ this, bool open, bool faceLeft = false)
{
	CSprite@ sprite = this.getSprite();
	if (open)
	{
		sprite.SetZ(-100.0f);
		sprite.SetAnimation("open");
		this.getShape().getConsts().collidable = false;
		this.getCurrentScript().tickFrequency = 3;
		sprite.SetFacingLeft(faceLeft);   // swing left or right
		Sound::Play("/DoorOpen.ogg", this.getPosition());
	}
	else
	{
		sprite.SetZ(100.0f);
		sprite.SetAnimation("close");
		this.getShape().getConsts().collidable = true;
		this.getCurrentScript().tickFrequency = 0;
		Sound::Play("/DoorClose.ogg", this.getPosition());
	}

	//TODO: fix flags sync and hitting
	//SetSolidFlag(this, !open);
}

void onTick(CBlob@ this)
{
	const uint count = this.getTouchingCount();
	for (uint step = 0; step < count; ++step)
	{
		CBlob@ blob = this.getTouchingByIndex(step);
		if (blob is null) continue;

		if (canOpenDoor(this, blob) && !isOpen(this))
		{
			OpenDoor(this, blob);
			break;
		}
	}
	// close it
	if (isOpen(this) && canClose(this))
	{
		setOpen(this, false);
	}
}


bool canClose(CBlob@ this)
{
	const uint count = this.getTouchingCount();
	uint collided = 0;
	for (uint step = 0; step < count; ++step)
	{
		CBlob@ blob = this.getTouchingByIndex(step);
		if (blob.isCollidable())
		{
			collided++;
		}
	}
	return collided == 0;
}

void onCollision(CBlob@ this, CBlob@ blob, bool solid)
{
	if (blob !is null)
	{
		this.getCurrentScript().tickFrequency = 3;
	}
}

void onEndCollision(CBlob@ this, CBlob@ blob)
{
	if (blob !is null)
	{
		if (canClose(this))
		{
			if (isOpen(this))
			{
				setOpen(this, false);
			}
			this.getCurrentScript().tickFrequency = 0;
		}
	}
}


bool canBePickedUp(CBlob@ this, CBlob@ byBlob)
{
	return false;
}

// this is such a pain - can't edit animations at the moment, so have to just carefully add destruction frames to the close animation >_>
f32 onHit(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitterBlob, u8 customData)
{
	if (customData == Hitters::boulder)
		return 0;

	//print("custom data: "+customData+" builder: "+Hitters::builder);
	if (customData == Hitters::builder)
		damage *= 2;
	if (customData == Hitters::drill)                //Hitters::saw is the drill hitter.... why //fixed
		damage *= 2;
	if (customData == Hitters::bomb)
		damage *= 1.3f;

	return damage;
}

void onHealthChange(CBlob@ this, f32 oldHealth)
{
	CSprite @sprite = this.getSprite();

	if (sprite !is null)
	{
		u8 frame = 0;

		Animation @destruction_anim = sprite.getAnimation("destruction");

		if (destruction_anim !is null)
		{
			f32 newHealth = this.getHealth();

			if (newHealth < this.getInitialHealth())
			{
				f32 ratio = newHealth / this.getInitialHealth();

				if (ratio <= 0.0f)
				{
					frame = destruction_anim.getFramesCount() - 1;
				}
				else
				{
					frame = (1.0f - ratio) * (destruction_anim.getFramesCount());
				}

				frame = destruction_anim.getFrame(frame);
			}
		}

		Animation @close_anim = sprite.getAnimation("close");
		u8 lastframe = close_anim.getFrame(close_anim.getFramesCount() - 1);
		if (lastframe < frame) // if our current final frame is less damaged than our door actually is
		{
			close_anim.RemoveFrame(lastframe);
			close_anim.AddFrame(frame); // replace the final frame by a more damaged one
		}
	}
}

bool doesCollideWithBlob(CBlob@ this, CBlob@ blob)
{
	if (isOpen(this))
		return false;

	if (canOpenDoor(this, blob))
	{
		OpenDoor(this, blob);
		return false;
	}

	return true;
}

void OpenDoor(CBlob@ this, CBlob@ blob, bool open = true)
{
	Vec2f pos = this.getPosition();
	Vec2f other_pos = blob.getPosition();
	Vec2f direction = Vec2f(1, 0);
	direction.RotateBy(this.getAngleDegrees());
	setOpen(this, open, ((pos - other_pos) * direction) < 0.0f);
}