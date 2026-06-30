import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, ForeignKey, Index, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class WorkoutProgram(Base):
    __tablename__ = "workout_programs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(index=True)  # NULL for global presets
    name: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text)
    program_type: Mapped[str | None] = mapped_column(String(100))
    days_per_week: Mapped[int]
    difficulty: Mapped[str | None] = mapped_column(String(50))
    is_preset: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=_utcnow, onupdate=_utcnow)

    days: Mapped[list["WorkoutProgramDay"]] = relationship(
        back_populates="program", cascade="all, delete-orphan", lazy="selectin"
    )


class WorkoutProgramDay(Base):
    __tablename__ = "workout_program_days"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    program_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("workout_programs.id", ondelete="CASCADE"))
    day_number: Mapped[int]
    day_name: Mapped[str | None] = mapped_column(String(100))
    focus: Mapped[str | None] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    program: Mapped["WorkoutProgram"] = relationship(back_populates="days")
    exercises: Mapped[list["WorkoutProgramExercise"]] = relationship(
        back_populates="program_day", cascade="all, delete-orphan", lazy="selectin"
    )


class WorkoutProgramExercise(Base):
    __tablename__ = "workout_program_exercises"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    program_day_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("workout_program_days.id", ondelete="CASCADE"))
    exercise_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("exercises.id"))
    set_count: Mapped[int]
    rep_min: Mapped[int | None] = mapped_column()
    rep_max: Mapped[int | None] = mapped_column()
    rest_seconds: Mapped[int | None] = mapped_column()
    exercise_order: Mapped[int]
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    program_day: Mapped["WorkoutProgramDay"] = relationship(back_populates="exercises")
    exercise: Mapped["Exercise"] = relationship(lazy="selectin")


class WorkoutSession(Base):
    __tablename__ = "workout_sessions"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    program_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("workout_programs.id", ondelete="SET NULL"))
    program_day_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("workout_program_days.id", ondelete="SET NULL"))
    started_at: Mapped[datetime]
    completed_at: Mapped[datetime | None] = mapped_column()
    duration_minutes: Mapped[int | None] = mapped_column()
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    sets: Mapped[list["WorkoutSet"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", lazy="selectin"
    )


class WorkoutSet(Base):
    __tablename__ = "workout_sets"
    # B6: a client-supplied idempotency key makes set logging replay-safe. The
    # uniqueness is PARTIAL — only enforced when client_set_id IS NOT NULL — so
    # legacy/server-minted sets (NULL key) are never blocked from coexisting.
    __table_args__ = (
        Index(
            "uq_workout_sets_session_client_set",
            "session_id",
            "client_set_id",
            unique=True,
            postgresql_where=text("client_set_id IS NOT NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("workout_sessions.id", ondelete="CASCADE"))
    exercise_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("exercises.id"))
    client_set_id: Mapped[uuid.UUID | None] = mapped_column()
    set_number: Mapped[int]
    reps: Mapped[int]
    weight_kg: Mapped[float | None] = mapped_column()
    rpe: Mapped[float | None] = mapped_column()
    is_pr: Mapped[bool] = mapped_column(Boolean, default=False)
    completed_at: Mapped[datetime] = mapped_column(default=_utcnow)

    session: Mapped["WorkoutSession"] = relationship(back_populates="sets")
    exercise: Mapped["Exercise"] = relationship(lazy="selectin")


class PersonalRecord(Base):
    __tablename__ = "personal_records"
    # B7: exactly one PR row per (user, exercise). Without this, two concurrent
    # first-PR inserts both succeed and a later scalar_one_or_none() raises
    # MultipleResultsFound, permanently 500-ing that user+exercise.
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "exercise_id",
            name="uq_personal_records_user_exercise",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    exercise_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("exercises.id"))
    max_weight_kg: Mapped[float | None] = mapped_column()
    max_reps_at_weight: Mapped[int | None] = mapped_column()
    estimated_1rm: Mapped[float | None] = mapped_column()
    achieved_at: Mapped[datetime]
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    exercise: Mapped["Exercise"] = relationship(lazy="selectin")
