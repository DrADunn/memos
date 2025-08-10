import dayjs from "dayjs";
import { CheckCircleIcon, Code2Icon, LinkIcon, ListTodoIcon, BookmarkIcon } from "lucide-react";
import { observer } from "mobx-react-lite";
import { useState, useCallback, useEffect, useMemo } from "react";
import { memoServiceClient } from "@/grpcweb";
import { extractUserIdFromName } from "@/store/common";
import { matchPath, useLocation } from "react-router-dom";
import useCurrentUser from "@/hooks/useCurrentUser";
import { useStatisticsData } from "@/hooks/useStatisticsData";
import { Routes } from "@/router";
import { userStore } from "@/store";
import memoFilterStore, { FilterFactor } from "@/store/memoFilter";
import { useTranslate } from "@/utils/i18n";
import ActivityCalendar from "../ActivityCalendar";
import { MonthNavigator } from "./MonthNavigator";
import { StatCard } from "./StatCard";

function countsByDate(memos: any[]): Record<string, number> {
  const map: Record<string, number> = {};
  for (const m of memos) {
    const tsSec =
      (m?.createdTs as number | undefined) ??
      (m?.createTime as number | undefined) ??
      (typeof m?.createdAt === "number" ? Math.floor(m.createdAt / 1000) : undefined);
    if (!tsSec) continue;
    const key = dayjs(tsSec * 1000).format("YYYY-MM-DD");
    map[key] = (map[key] || 0) + 1;
  }
  return map;
}

function buildFilterConds(userName: string, monthStr: string): string[] {
  const uid = extractUserIdFromName(userName);
  const start = dayjs(monthStr).startOf("month").toISOString();
  const end = dayjs(monthStr).endOf("month").toISOString();
  const conds: string[] = [`creator_id == ${uid}`, `display_time >= "${start}"`, `display_time <= "${end}"`];

  const filters = (memoFilterStore as any)?.state?.filters ?? [];
  for (const f of filters as Array<{ factor: string; value?: string }>) {
    switch (f.factor) {
      case "pinned":
        conds.push(`pinned == true`);
        break;
      case "property.hasLink":
        conds.push(`has_link == true`);
        break;
      case "property.hasCode":
        conds.push(`has_code == true`);
        break;
      case "property.hasTaskList":
        conds.push(`has_task_list == true`);
        break;
      case "tag":
      case "tags":
        if (f.value) conds.push(`tag == "${f.value}"`);
        break;
      case "displayTime":
        // 单日点击由 onClick 处理，这里只做整月
        break;
      default:
        break;
    }
  }
  return conds;
}

const StatisticsView = observer(() => {
  const t = useTranslate();
  const location = useLocation();
  const currentUser = useCurrentUser();
  const { memoTypeStats, activityStats } = useStatisticsData();
  const [selectedDate] = useState(new Date());
  const [visibleMonthString, setVisibleMonthString] = useState(dayjs().format("YYYY-MM"));
  const [monthMemos, setMonthMemos] = useState<any[] | null>(null);

  useEffect(() => {
    if (!currentUser?.name) return;
    const conds = buildFilterConds(currentUser.name, visibleMonthString);
    memoServiceClient
      .listMemos({ filter: conds.join(" && "), pageSize: 1000 })
      .then(({ memos }) => setMonthMemos(memos || []))
      .catch(() => setMonthMemos(null));
    // 依赖里加入筛选集合的快照，保证筛选变化时重拉
  }, [currentUser?.name, visibleMonthString, useMemo(() => JSON.stringify((memoFilterStore as any)?.state?.filters ?? []), [(memoFilterStore as any)?.state?.filters])]);
  
  const calendarData: Record<string, number> = useMemo(() => {
    if (Array.isArray(monthMemos)) return countsByDate(monthMemos);
    return activityStats;
  }, [monthMemos, activityStats]);

  const handleCalendarClick = useCallback((date: string) => {
    memoFilterStore.removeFilter((f) => f.factor === "displayTime");
    memoFilterStore.addFilter({ factor: "displayTime", value: date });
  }, []);

  const handleFilterClick = useCallback((factor: FilterFactor, value: string = "") => {
    memoFilterStore.addFilter({ factor, value });
  }, []);

  const isRootPath = matchPath(Routes.ROOT, location.pathname);
  const hasPinnedMemos = currentUser && (userStore.state.currentUserStats?.pinnedMemos || []).length > 0;

  return (
    <div className="group w-full mt-2 space-y-1 text-muted-foreground animate-fade-in">
      <MonthNavigator visibleMonth={visibleMonthString} onMonthChange={setVisibleMonthString} />

      <div className="w-full animate-scale-in">
        <ActivityCalendar
          month={visibleMonthString}
          selectedDate={selectedDate.toDateString()}
          data={calendarData}
          onClick={handleCalendarClick}
        />
      </div>

      <div className="pt-1 w-full flex flex-row justify-start items-center gap-1 flex-wrap">
        {isRootPath && hasPinnedMemos && (
          <StatCard
            icon={<BookmarkIcon className="w-4 h-auto mr-1 opacity-70" />}
            label={t("common.pinned")}
            count={userStore.state.currentUserStats!.pinnedMemos.length}
            onClick={() => handleFilterClick("pinned")}
          />
        )}

        <StatCard
          icon={<LinkIcon className="w-4 h-auto mr-1 opacity-70" />}
          label={t("memo.links")}
          count={memoTypeStats.linkCount}
          onClick={() => handleFilterClick("property.hasLink")}
        />

        <StatCard
          icon={
            memoTypeStats.undoCount > 0 ? (
              <ListTodoIcon className="w-4 h-auto mr-1 opacity-70" />
            ) : (
              <CheckCircleIcon className="w-4 h-auto mr-1 opacity-70" />
            )
          }
          label={t("memo.to-do")}
          count={
            memoTypeStats.undoCount > 0 ? (
              <div className="text-sm flex flex-row items-start justify-center">
                <span className="truncate">{memoTypeStats.todoCount - memoTypeStats.undoCount}</span>
                <span className="font-mono opacity-50">/</span>
                <span className="truncate">{memoTypeStats.todoCount}</span>
              </div>
            ) : (
              memoTypeStats.todoCount
            )
          }
          onClick={() => handleFilterClick("property.hasTaskList")}
          tooltip={memoTypeStats.undoCount > 0 ? "Done / Total" : undefined}
        />

        <StatCard
          icon={<Code2Icon className="w-4 h-auto mr-1 opacity-70" />}
          label={t("memo.code")}
          count={memoTypeStats.codeCount}
          onClick={() => handleFilterClick("property.hasCode")}
        />
      </div>
    </div>
  );
});

export default StatisticsView;
