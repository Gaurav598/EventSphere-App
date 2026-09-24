from fastapi import APIRouter, Depends, Query, Body
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field
from typing import Literal
from app.services.admin_service import AdminService
from app.dependencies.auth import require_admin
from app.models.user import UserInDB
from app.models.event import EventCreate, EventUpdate

class StatusUpdate(BaseModel):
    status: Literal["confirmed", "rejected"]

class CheckinRequest(BaseModel):
    ticketPayload: str = Field(min_length=20, max_length=4096)

router = APIRouter()

# -----------------
# Event Management
# -----------------
@router.get("/events")
async def get_my_events(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    current_admin: UserInDB = Depends(require_admin)
):
    result = await AdminService.get_events(str(current_admin.id), page, limit)
    return {
        "success": True,
        "data": result["items"],
        "pagination": result["pagination"],
        "message": "Admin events retrieved successfully"
    }

@router.post("/events", status_code=201)
async def create_event(event_data: EventCreate, current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.create_event(event_data, str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Event created successfully"
    }

@router.put("/events/{event_id}")
async def update_event(event_id: str, event_data: EventUpdate, current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.update_event(event_id, event_data, str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Event updated successfully"
    }

@router.delete("/events/{event_id}")
async def delete_event(event_id: str, current_admin: UserInDB = Depends(require_admin)):
    await AdminService.delete_event(event_id, str(current_admin.id))
    return {
        "success": True,
        "data": None,
        "message": "Event deleted successfully"
    }

@router.patch("/events/{event_id}/close-registration")
async def close_registration(event_id: str, current_admin: UserInDB = Depends(require_admin)):
    await AdminService.close_registration(event_id, str(current_admin.id))
    return {
        "success": True,
        "data": None,
        "message": "Event registration closed successfully"
    }

@router.get("/events/{event_id}/registrations")
async def get_event_registrations(event_id: str, current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.get_event_registrations(event_id, str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Registrations retrieved successfully"
    }

@router.get("/events/{event_id}/registrations/export")
async def export_event_registrations(event_id: str, current_admin: UserInDB = Depends(require_admin)):
    csv_data = await AdminService.export_registrations(event_id, str(current_admin.id))
    return PlainTextResponse(
        content=csv_data,
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename=registrations_{event_id}.csv"}
    )

@router.put("/registrations/{registration_id}/status")
async def update_registration_status(
    registration_id: str, 
    payload: StatusUpdate,
    current_admin: UserInDB = Depends(require_admin)
):
    result = await AdminService.update_registration_status(registration_id, payload.status, str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": f"Registration status updated to {payload.status}"
    }

@router.post("/events/{event_id}/checkin")
async def checkin_attendee(
    event_id: str,
    payload: CheckinRequest,
    current_admin: UserInDB = Depends(require_admin)
):
    result = await AdminService.checkin_attendee(event_id, payload.ticketPayload, str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": result["message"]
    }

# -----------------
# Analytics
# -----------------
@router.get("/analytics/top-events")
async def top_events(current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.get_top_events(str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Top events retrieved successfully"
    }

@router.get("/analytics/category-wise")
async def category_wise(current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.get_category_wise(str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Category wise analytics retrieved successfully"
    }

@router.get("/analytics/monthly-trend")
async def monthly_trend(current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.get_monthly_trend(str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Monthly trend retrieved successfully"
    }

@router.get("/analytics/summary")
async def analytics_summary(current_admin: UserInDB = Depends(require_admin)):
    result = await AdminService.get_analytics_summary(str(current_admin.id))
    return {
        "success": True,
        "data": result,
        "message": "Analytics summary retrieved successfully"
    }
